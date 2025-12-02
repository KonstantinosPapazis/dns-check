#!/bin/bash
# =============================================================================
# Quick DNS Geolocation Check Script
# Run this from AWS CloudShell in each region to test routing
#
# Usage: 
#   ./quick_check.sh myapp.kostas.com
#   ./quick_check.sh myapp.kostas.com /health
# =============================================================================

DOMAIN="${1:-myapp.kostas.com}"
ENDPOINT="${2:-/health}"
URL="https://${DOMAIN}${ENDPOINT}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=============================================="
echo "🌍 DNS Geolocation Quick Check"
echo "=============================================="
echo ""

# Get current region from CloudShell/EC2 metadata
CURRENT_REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region 2>/dev/null || echo "${AWS_REGION:-unknown}")
echo "📍 Running from region: ${CURRENT_REGION}"
echo "🔗 Target URL: ${URL}"
echo ""

# DNS Resolution
echo "1️⃣  DNS Resolution"
echo "   Resolving ${DOMAIN}..."
RESOLVED_IPS=$(dig +short ${DOMAIN} 2>/dev/null | head -5)
if [ -z "$RESOLVED_IPS" ]; then
    RESOLVED_IPS=$(host ${DOMAIN} 2>/dev/null | grep "has address" | awk '{print $4}' | head -5)
fi
echo "   IPs: ${RESOLVED_IPS:-"Could not resolve"}"
echo ""

# HTTP Request with timing
echo "2️⃣  HTTP Request"
CURL_OUTPUT=$(curl -sS -w "\n__METRICS__\nhttp_code:%{http_code}\nremote_ip:%{remote_ip}\ntime_namelookup:%{time_namelookup}\ntime_connect:%{time_connect}\ntime_total:%{time_total}\n" \
    --connect-timeout 10 \
    -H "User-Agent: QuickCheck/${CURRENT_REGION}" \
    "${URL}" 2>&1)

# Split response body and metrics
BODY=$(echo "$CURL_OUTPUT" | sed -n '1,/__METRICS__/p' | head -n -1)
HTTP_CODE=$(echo "$CURL_OUTPUT" | grep "http_code:" | cut -d: -f2)
REMOTE_IP=$(echo "$CURL_OUTPUT" | grep "remote_ip:" | cut -d: -f2)
TIME_TOTAL=$(echo "$CURL_OUTPUT" | grep "time_total:" | cut -d: -f2)

echo "   Status: ${HTTP_CODE}"
echo "   Connected to IP: ${REMOTE_IP}"
echo "   Response time: ${TIME_TOTAL}s"
echo ""

# Check response headers
echo "3️⃣  Response Headers (region indicators)"
HEADERS=$(curl -sI --connect-timeout 10 "${URL}" 2>/dev/null)
echo "$HEADERS" | grep -iE "(x-served|x-region|server|x-amz|x-cache|cf-ray|via)" | head -10 | sed 's/^/   /'
echo ""

# Parse body for region info
echo "4️⃣  Response Body (looking for region)"
echo "   Preview:"
echo "$BODY" | head -c 500 | sed 's/^/   /'
echo ""

# Try to extract region from JSON
SERVED_REGION=$(echo "$BODY" | grep -oP '"region"\s*:\s*"\K[^"]+' 2>/dev/null || \
                echo "$BODY" | grep -oE '"region"[[:space:]]*:[[:space:]]*"[^"]+"' | cut -d'"' -f4)

if [ -n "$SERVED_REGION" ]; then
    echo ""
    echo "=============================================="
    if [ "$SERVED_REGION" == "$CURRENT_REGION" ]; then
        echo -e "✅ ${GREEN}MATCH${NC}: Request from ${CURRENT_REGION} served by ${SERVED_REGION}"
    else
        echo -e "❌ ${RED}MISMATCH${NC}: Request from ${CURRENT_REGION} served by ${SERVED_REGION}"
    fi
    echo "=============================================="
else
    echo ""
    echo "=============================================="
    echo -e "⚠️  ${YELLOW}Could not determine serving region from response${NC}"
    echo "   Make sure your app returns region in JSON body or headers"
    echo "=============================================="
fi

echo ""
echo "📋 Raw response for debugging:"
echo "---"
echo "$BODY" | head -20

