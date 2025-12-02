#!/bin/bash
# =============================================================================
# Run quick check from all 3 regions using AWS CloudShell
# 
# This script uses AWS CLI to invoke commands in CloudShell across regions.
# Alternatively, just open 3 CloudShell tabs and run quick_check.sh manually.
#
# Usage: ./check_all_regions.sh myapp.kostas.com
# =============================================================================

DOMAIN="${1:-myapp.kostas.com}"
ENDPOINT="${2:-/health}"
REGIONS=("us-east-1" "eu-west-1" "ap-southeast-1")

echo "=============================================="
echo "🌍 Multi-Region Geolocation Check"
echo "Domain: ${DOMAIN}"
echo "=============================================="
echo ""
echo "⚠️  This script shows how to test from each region."
echo "   Open AWS CloudShell in each region and run:"
echo ""
echo "   curl -sS https://${DOMAIN}${ENDPOINT} | python3 -c \\"
echo "     \"import sys,json; d=json.load(sys.stdin); print('Region:', d.get('region','unknown'))\""
echo ""
echo "=============================================="
echo ""

# Quick local test (from your current location)
echo "📍 Testing from YOUR current location:"
echo "---"

RESULT=$(curl -sS "https://${DOMAIN}${ENDPOINT}" 2>/dev/null)
if [ $? -eq 0 ]; then
    echo "Response: ${RESULT}" | head -c 500
    echo ""
    
    # Try to extract region
    REGION=$(echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('region',''))" 2>/dev/null)
    if [ -n "$REGION" ]; then
        echo ""
        echo "Served by region: ${REGION}"
    fi
else
    echo "Failed to connect"
fi

echo ""
echo "=============================================="
echo ""
echo "To test from AWS regions, open CloudShell in each region:"
echo ""

for region in "${REGIONS[@]}"; do
    echo "🌐 ${region}:"
    echo "   1. Go to: https://${region}.console.aws.amazon.com/cloudshell"
    echo "   2. Run: curl -sS https://${DOMAIN}${ENDPOINT}"
    echo ""
done

