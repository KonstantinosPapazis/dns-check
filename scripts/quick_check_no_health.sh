#!/bin/bash
# =============================================================================
# Quick DNS Geolocation Check - NO /health endpoint required
# 
# This script checks routing using:
# 1. DNS resolution (what IPs resolve in this region)
# 2. Response latency (local region should be fastest)
# 3. Any headers the F5 or backend might add
# 4. TLS certificate info (might indicate regional deployment)
#
# Run from AWS CloudShell in each region:
#   ./quick_check_no_health.sh myapp.kostas.com
# =============================================================================

DOMAIN="${1:-myapp.kostas.com}"
URL="https://${DOMAIN}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo "=============================================="
echo -e "${BOLD}🌍 DNS Geolocation Check (No /health endpoint)${NC}"
echo "=============================================="
echo ""

# Get current region
CURRENT_REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region 2>/dev/null || echo "${AWS_REGION:-$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document 2>/dev/null | grep region | cut -d'"' -f4)}")
CURRENT_REGION="${CURRENT_REGION:-unknown}"

echo -e "📍 Probing from: ${BOLD}${CURRENT_REGION}${NC}"
echo -e "🔗 Target: ${URL}"
echo ""

# =============================================================================
# 1. DNS Resolution
# =============================================================================
echo -e "${BOLD}1️⃣  DNS Resolution${NC}"
echo "   What IPs does ${DOMAIN} resolve to from here?"
echo ""

# Try dig first, fall back to host, then nslookup
if command -v dig &> /dev/null; then
    echo "   Using dig:"
    dig +short ${DOMAIN} 2>/dev/null | head -5 | sed 's/^/   → /'
    echo ""
    echo "   Full DNS trace:"
    dig ${DOMAIN} +trace 2>/dev/null | grep -E "^${DOMAIN}|IN\s+A" | tail -5 | sed 's/^/   /'
elif command -v host &> /dev/null; then
    host ${DOMAIN} 2>/dev/null | grep "has address" | sed 's/^/   → /'
else
    nslookup ${DOMAIN} 2>/dev/null | grep "Address:" | tail -n +2 | sed 's/^/   → /'
fi
echo ""

# =============================================================================
# 2. Connection Details
# =============================================================================
echo -e "${BOLD}2️⃣  Connection Details${NC}"
echo ""

# Get connection info using curl
CURL_RESULT=$(curl -sS -w '\n__CURL_METRICS__\nremote_ip:%{remote_ip}\nremote_port:%{remote_port}\nlocal_ip:%{local_ip}\ntime_namelookup:%{time_namelookup}\ntime_connect:%{time_connect}\ntime_appconnect:%{time_appconnect}\ntime_total:%{time_total}\nhttp_code:%{http_code}\nssl_verify_result:%{ssl_verify_result}\n' \
    -o /dev/null \
    --connect-timeout 10 \
    "${URL}" 2>&1)

REMOTE_IP=$(echo "$CURL_RESULT" | grep "remote_ip:" | cut -d: -f2)
TIME_LOOKUP=$(echo "$CURL_RESULT" | grep "time_namelookup:" | cut -d: -f2)
TIME_CONNECT=$(echo "$CURL_RESULT" | grep "time_connect:" | cut -d: -f2)
TIME_SSL=$(echo "$CURL_RESULT" | grep "time_appconnect:" | cut -d: -f2)
TIME_TOTAL=$(echo "$CURL_RESULT" | grep "time_total:" | cut -d: -f2)
HTTP_CODE=$(echo "$CURL_RESULT" | grep "http_code:" | cut -d: -f2)

echo "   Connected to IP: ${REMOTE_IP}"
echo "   HTTP Status: ${HTTP_CODE}"
echo ""
echo "   Timing breakdown:"
echo "   → DNS lookup:    ${TIME_LOOKUP}s"
echo "   → TCP connect:   ${TIME_CONNECT}s"
echo "   → SSL handshake: ${TIME_SSL}s"
echo "   → Total time:    ${TIME_TOTAL}s"
echo ""

# Latency hint
if command -v bc &> /dev/null; then
    CONNECT_MS=$(echo "$TIME_CONNECT * 1000" | bc 2>/dev/null | cut -d. -f1)
    if [ -n "$CONNECT_MS" ]; then
        if [ "$CONNECT_MS" -lt 50 ]; then
            echo -e "   ${GREEN}⚡ Very low latency (<50ms) - likely same region${NC}"
        elif [ "$CONNECT_MS" -lt 150 ]; then
            echo -e "   ${YELLOW}📶 Medium latency (50-150ms) - possibly nearby region${NC}"
        else
            echo -e "   ${RED}🐌 High latency (>150ms) - likely distant region${NC}"
        fi
    fi
fi
echo ""

# =============================================================================
# 3. Response Headers (looking for region hints)
# =============================================================================
echo -e "${BOLD}3️⃣  Response Headers (looking for region hints)${NC}"
echo ""

HEADERS=$(curl -sI --connect-timeout 10 "${URL}" 2>/dev/null)

# Headers that might indicate region/server
echo "$HEADERS" | grep -iE "^(server|x-|via|cf-|set-cookie|location):" | head -20 | while read line; do
    # Highlight if contains region-like strings
    if echo "$line" | grep -qiE "(east|west|eu|ap|us-|region|pool|node|server|backend)"; then
        echo -e "   ${GREEN}→ $line${NC}"
    else
        echo "   $line"
    fi
done

echo ""

# =============================================================================
# 4. TLS Certificate Details
# =============================================================================
echo -e "${BOLD}4️⃣  TLS Certificate Info${NC}"
echo ""

CERT_INFO=$(echo | openssl s_client -connect ${DOMAIN}:443 -servername ${DOMAIN} 2>/dev/null | openssl x509 -noout -subject -issuer -dates 2>/dev/null)
echo "$CERT_INFO" | sed 's/^/   /'
echo ""

# Check for any SAN entries that might indicate region
echo "   Subject Alternative Names:"
echo | openssl s_client -connect ${DOMAIN}:443 -servername ${DOMAIN} 2>/dev/null | openssl x509 -noout -text 2>/dev/null | grep -A1 "Subject Alternative Name" | tail -1 | tr ',' '\n' | head -5 | sed 's/^/   → /'
echo ""

# =============================================================================
# 5. Traceroute (optional - shows network path)
# =============================================================================
echo -e "${BOLD}5️⃣  Network Path (first 5 hops)${NC}"
echo ""

if command -v traceroute &> /dev/null; then
    traceroute -m 5 -w 2 ${DOMAIN} 2>/dev/null | sed 's/^/   /'
elif command -v tracepath &> /dev/null; then
    tracepath -m 5 ${DOMAIN} 2>/dev/null | head -6 | sed 's/^/   /'
else
    echo "   (traceroute not available)"
fi
echo ""

# =============================================================================
# 6. IP Geolocation Lookup (if available)
# =============================================================================
echo -e "${BOLD}6️⃣  IP Geolocation (querying ip-api.com)${NC}"
echo ""

if [ -n "$REMOTE_IP" ]; then
    GEO=$(curl -s "http://ip-api.com/json/${REMOTE_IP}?fields=status,country,regionName,city,isp,org" 2>/dev/null)
    if echo "$GEO" | grep -q '"status":"success"'; then
        echo "   Server IP: ${REMOTE_IP}"
        echo "$GEO" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(f\"   Country: {d.get('country', 'N/A')}\")
print(f\"   Region: {d.get('regionName', 'N/A')}\")
print(f\"   City: {d.get('city', 'N/A')}\")
print(f\"   ISP: {d.get('isp', 'N/A')}\")
print(f\"   Org: {d.get('org', 'N/A')}\")
" 2>/dev/null || echo "   (Could not parse response)"
    else
        echo "   Could not get geolocation for ${REMOTE_IP}"
    fi
else
    echo "   (No IP to look up)"
fi
echo ""

# =============================================================================
# Summary
# =============================================================================
echo "=============================================="
echo -e "${BOLD}📊 SUMMARY${NC}"
echo "=============================================="
echo ""
echo "   Probe Region:    ${CURRENT_REGION}"
echo "   Resolved IP:     ${REMOTE_IP}"
echo "   Response Time:   ${TIME_TOTAL}s"
echo ""
echo -e "${YELLOW}⚠️  Without a /health endpoint returning region info,${NC}"
echo -e "${YELLOW}   we can only infer routing from:${NC}"
echo "   • Response latency (lower = likely closer)"
echo "   • IP geolocation (shows F5/LB location, not ECS)"
echo "   • Any X- headers the infra adds"
echo ""
echo "💡 Recommendations:"
echo "   1. Ask devs to add region header to responses:"
echo "      response.headers['X-Served-By-Region'] = region"
echo ""
echo "   2. Or configure F5 to add a header indicating the pool:"
echo "      X-F5-Pool: pool-eu-west-1"
echo ""
echo "=============================================="

