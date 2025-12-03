#!/bin/bash
# Manual region verification script using command-line tools
# Usage: ./check_region.sh [domain] [protocol]

set -e

DOMAIN="${1:-myapp.kostas.com}"
PROTOCOL="${2:-https}"
HEALTH_PATH="${3:-/health}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "=========================================="
echo "Region Verification for: $DOMAIN"
echo "=========================================="
echo ""

# Check dependencies
command -v dig >/dev/null 2>&1 || { echo "Error: dig is required but not installed." >&2; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "Error: curl is required but not installed." >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "Warning: jq not found. Some features may not work." >&2; }

# 1. DNS Resolution
echo -e "${BLUE}1. DNS Resolution${NC}"
echo "------------------"
IPS=$(dig +short "$DOMAIN" 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' || echo "")
if [ -z "$IPS" ]; then
    IPS=$(nslookup "$DOMAIN" 2>/dev/null | grep -A 1 "Name:" | tail -1 | awk '{print $2}' || echo "")
fi

if [ -z "$IPS" ]; then
    echo -e "${RED}✗ Could not resolve domain${NC}"
    exit 1
fi

echo "Resolved IP addresses:"
for IP in $IPS; do
    echo "  • $IP"
done
echo ""

# 2. IP Geolocation
echo -e "${BLUE}2. IP Geolocation${NC}"
echo "-----------------"
for IP in $IPS; do
    echo "Checking IP: $IP"
    
    if command -v jq >/dev/null 2>&1; then
        # Using ipapi.co
        GEO_DATA=$(curl -s "https://ipapi.co/$IP/json/" 2>/dev/null || echo "")
        if [ -n "$GEO_DATA" ]; then
            REGION=$(echo "$GEO_DATA" | jq -r '.region // .region_code // "unknown"' 2>/dev/null || echo "unknown")
            COUNTRY=$(echo "$GEO_DATA" | jq -r '.country_code // "unknown"' 2>/dev/null || echo "unknown")
            CITY=$(echo "$GEO_DATA" | jq -r '.city // "unknown"' 2>/dev/null || echo "unknown")
            ORG=$(echo "$GEO_DATA" | jq -r '.org // "unknown"' 2>/dev/null || echo "unknown")
            
            echo "  Location: $CITY, $REGION, $COUNTRY"
            echo "  Organization: $ORG"
            
            if echo "$ORG" | grep -qi "amazon\|aws"; then
                echo -e "  ${GREEN}✓ AWS IP detected${NC}"
            fi
        fi
    else
        echo "  (Install jq for detailed geolocation)"
    fi
    echo ""
done

# 3. AWS IP Range Check
echo -e "${BLUE}3. AWS IP Range Check${NC}"
echo "---------------------"
echo "Checking against AWS published IP ranges..."

AWS_RANGES_FILE="/tmp/aws-ip-ranges-$$.json"
curl -s "https://ip-ranges.amazonaws.com/ip-ranges.json" > "$AWS_RANGES_FILE" 2>/dev/null || {
    echo -e "${YELLOW}⚠ Could not fetch AWS IP ranges${NC}"
    rm -f "$AWS_RANGES_FILE"
}

if [ -f "$AWS_RANGES_FILE" ] && command -v jq >/dev/null 2>&1; then
    for IP in $IPS; do
        echo "Checking IP: $IP"
        # Simple prefix matching (first two octets)
        PREFIX=$(echo "$IP" | cut -d. -f1-2)
        
        MATCHES=$(jq -r --arg prefix "$PREFIX" \
            '.prefixes[] | select(.ip_prefix | startswith($prefix)) | "\(.region) - \(.service) - \(.ip_prefix)"' \
            "$AWS_RANGES_FILE" 2>/dev/null | head -5)
        
        if [ -n "$MATCHES" ]; then
            echo -e "  ${GREEN}✓ Found in AWS IP ranges:${NC}"
            echo "$MATCHES" | sed 's/^/    /'
        else
            echo -e "  ${YELLOW}? Not found in AWS IP ranges (may be behind CDN/LB)${NC}"
        fi
        echo ""
    done
    rm -f "$AWS_RANGES_FILE"
else
    echo -e "${YELLOW}⚠ AWS IP range check skipped (jq not available or download failed)${NC}"
    echo ""
fi

# 4. HTTP Headers
echo -e "${BLUE}4. HTTP Response Headers${NC}"
echo "------------------------"
URL="$PROTOCOL://$DOMAIN$HEALTH_PATH"
echo "Checking: $URL"

HEADERS=$(curl -s -I "$URL" 2>&1)
if [ $? -eq 0 ]; then
    REGION_HEADERS=$(echo "$HEADERS" | grep -iE "region|location|edge|x-" || echo "")
    if [ -n "$REGION_HEADERS" ]; then
        echo -e "${GREEN}Region-related headers found:${NC}"
        echo "$REGION_HEADERS" | sed 's/^/  /'
    else
        echo -e "${YELLOW}No region headers found${NC}"
        echo "All headers:"
        echo "$HEADERS" | sed 's/^/  /'
    fi
else
    echo -e "${RED}✗ Failed to connect${NC}"
fi
echo ""

# 5. Response Time
echo -e "${BLUE}5. Response Time Measurement${NC}"
echo "----------------------------"
echo "Measuring latency (lower = closer region):"

TIMES=()
for i in {1..5}; do
    TIME=$(curl -s -o /dev/null -w "%{time_total}" "$URL" 2>/dev/null || echo "0")
    if [ "$TIME" != "0" ]; then
        TIMES+=($TIME)
        printf "  Attempt %d: %.3fs\n" $i $TIME
    fi
done

if [ ${#TIMES[@]} -gt 0 ]; then
    # Calculate average, min, max (using awk for portability)
    AVG=$(printf '%s\n' "${TIMES[@]}" | awk '{sum+=$1; count++} END {if(count>0) print sum/count; else print 0}')
    MIN=$(printf '%s\n' "${TIMES[@]}" | awk 'BEGIN{min=999} {if($1<min) min=$1} END{print min}')
    MAX=$(printf '%s\n' "${TIMES[@]}" | awk 'BEGIN{max=0} {if($1>max) max=$1} END{print max}')
    
    echo ""
    echo "  Average: ${AVG}s"
    echo "  Min: ${MIN}s"
    echo "  Max: ${MAX}s"
    
    # Provide guidance (convert to milliseconds)
    AVG_MS=$(echo "$AVG * 1000" | awk '{printf "%.0f", $1}')
    if [ "$AVG_MS" -lt 50 ] 2>/dev/null; then
        echo -e "  ${GREEN}✓ Very low latency - likely same region or very close${NC}"
    elif [ "$AVG_MS" -lt 150 ] 2>/dev/null; then
        echo -e "  ${YELLOW}⚠ Moderate latency - same continent, different region${NC}"
    else
        echo -e "  ${YELLOW}⚠ High latency - different continent${NC}"
    fi
else
    echo -e "${RED}✗ Could not measure latency${NC}"
fi
echo ""

# 6. Summary
echo "=========================================="
echo -e "${BLUE}Summary${NC}"
echo "=========================================="
echo "Domain: $DOMAIN"
echo "IP Addresses: $(echo $IPS | tr '\n' ' ')"
if [ -n "$AVG" ]; then
    echo "Average Latency: ${AVG}s"
fi
echo ""
echo "Expected Latency Ranges:"
echo "  • Same region: 10-50ms"
echo "  • Same continent: 50-150ms"
echo "  • Different continent: 150-300ms+"
echo ""
echo -e "${YELLOW}Note:${NC} Lower latency typically indicates closer region."
echo "F5 load balancer should route to the closest region based on your location."
echo ""

