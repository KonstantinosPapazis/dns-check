#!/bin/bash
# Simple region check - minimal dependencies
# Usage: ./check_region_simple.sh [domain]

DOMAIN="${1:-myapp.kostas.com}"

echo "=========================================="
echo "Simple Region Check for: $DOMAIN"
echo "=========================================="
echo ""

# 1. DNS Resolution
echo "1. DNS Resolution:"
IP=$(dig +short "$DOMAIN" 2>/dev/null | head -1 || nslookup "$DOMAIN" 2>/dev/null | grep -A 1 "Name:" | tail -1 | awk '{print $2}')
if [ -z "$IP" ]; then
    echo "  ✗ Could not resolve domain"
    exit 1
fi
echo "  IP: $IP"
echo ""

# 2. Basic IP Info (using free API)
echo "2. IP Geolocation:"
GEO=$(curl -s "https://ipapi.co/$IP/json/" 2>/dev/null)
if [ -n "$GEO" ]; then
    echo "$GEO" | grep -E '"city"|"region"|"country_code"|"org"' | sed 's/^/  /'
else
    echo "  (Could not fetch geolocation data)"
fi
echo ""

# 3. HTTP Headers
echo "3. HTTP Headers:"
HEADERS=$(curl -s -I "https://$DOMAIN/health" 2>&1)
if echo "$HEADERS" | grep -qi "region\|location"; then
    echo "$HEADERS" | grep -i "region\|location" | sed 's/^/  /'
else
    echo "  No region headers found"
fi
echo ""

# 4. Latency
echo "4. Latency:"
TIME=$(curl -s -o /dev/null -w "%{time_total}" "https://$DOMAIN/health" 2>/dev/null)
if [ -n "$TIME" ]; then
    TIME_MS=$(echo "$TIME * 1000" | awk '{printf "%.0f", $1}')
    echo "  Response time: ${TIME}s (${TIME_MS}ms)"
    if [ "$TIME_MS" -lt 50 ] 2>/dev/null; then
        echo "  → Very fast - likely same region"
    elif [ "$TIME_MS" -lt 150 ] 2>/dev/null; then
        echo "  → Moderate - same continent"
    else
        echo "  → Slow - different continent"
    fi
else
    echo "  Could not measure"
fi
echo ""

echo "Done!"

