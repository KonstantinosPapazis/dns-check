#!/bin/bash
# =============================================================================
# DEFINITIVE REGION TEST
# 
# This test PROVES which ECS region handles your request by:
# 1. Making a request with a unique identifier
# 2. Searching CloudWatch logs in ALL regions for that identifier
# 3. Only the region that processed the request will have the log entry
#
# Usage:
#   ./definitive_region_test.sh myapp.kostas.com /ecs/your-log-group
#
# Run this from EACH region (CloudShell or ECS) to verify routing
# =============================================================================

DOMAIN="${1:-myapp.kostas.com}"
LOG_GROUP="${2:-/ecs/your-service}"
REGIONS="${3:-eu-west-2 ap-southeast-1 us-east-1}"

# Generate unique request ID
REQUEST_ID="region-test-$(date +%s)-$RANDOM"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

echo "=============================================="
echo -e "${BOLD}🔍 DEFINITIVE REGION TEST${NC}"
echo "=============================================="
echo ""

# Get current region
CURRENT_REGION=$(curl -s ${ECS_CONTAINER_METADATA_URI_V4}/task 2>/dev/null | jq -r '.AvailabilityZone' | sed 's/[a-z]$//' || \
                 curl -s http://169.254.169.254/latest/meta-data/placement/region 2>/dev/null || \
                 echo "${AWS_REGION:-unknown}")

echo -e "📍 Testing FROM: ${BOLD}${CURRENT_REGION}${NC}"
echo -e "🎯 Target: https://${DOMAIN}"
echo -e "🏷️  Request ID: ${BOLD}${REQUEST_ID}${NC}"
echo -e "📋 Log Group: ${LOG_GROUP}"
echo ""

# Step 1: Make the request with unique ID
echo "Step 1: Making request with unique identifier..."
echo "----------------------------------------------"

HTTP_CODE=$(curl -sS -o /dev/null -w "%{http_code}" \
    -H "X-Request-ID: ${REQUEST_ID}" \
    -H "X-Test-From-Region: ${CURRENT_REGION}" \
    -H "User-Agent: RegionTest/${REQUEST_ID}" \
    "https://${DOMAIN}" 2>/dev/null)

if [ "$HTTP_CODE" -ge 200 ] && [ "$HTTP_CODE" -lt 400 ]; then
    echo -e "   ${GREEN}✓ Request sent successfully (HTTP ${HTTP_CODE})${NC}"
else
    echo -e "   ${RED}✗ Request failed (HTTP ${HTTP_CODE})${NC}"
    exit 1
fi
echo ""

# Wait for logs to propagate
echo "Step 2: Waiting 10 seconds for logs to propagate..."
echo "----------------------------------------------"
sleep 10
echo "   Done waiting."
echo ""

# Step 3: Search logs in all regions
echo "Step 3: Searching logs in all regions..."
echo "----------------------------------------------"
echo ""

FOUND_IN=""

for region in $REGIONS; do
    echo -n "   Checking ${region}... "
    
    # Search for the request ID in logs
    RESULT=$(aws logs filter-log-events \
        --log-group-name "${LOG_GROUP}" \
        --filter-pattern "${REQUEST_ID}" \
        --start-time $(($(date +%s) * 1000 - 60000)) \
        --region "${region}" \
        --query 'events[*].message' \
        --output text 2>/dev/null)
    
    if [ -n "$RESULT" ] && [ "$RESULT" != "None" ]; then
        echo -e "${GREEN}FOUND!${NC}"
        FOUND_IN="${region}"
    else
        echo "not found"
    fi
done

echo ""
echo "=============================================="
echo -e "${BOLD}📊 RESULT${NC}"
echo "=============================================="
echo ""

if [ -n "$FOUND_IN" ]; then
    echo -e "   Request from: ${BOLD}${CURRENT_REGION}${NC}"
    echo -e "   Handled by:   ${BOLD}${FOUND_IN}${NC}"
    echo ""
    
    if [ "$CURRENT_REGION" == "$FOUND_IN" ]; then
        echo -e "   ${GREEN}✅ GEOLOCATION ROUTING IS CORRECT!${NC}"
        echo -e "   ${GREEN}   Request stayed in the same region.${NC}"
    else
        echo -e "   ${RED}❌ GEOLOCATION ROUTING FAILURE!${NC}"
        echo -e "   ${RED}   Request was routed to a DIFFERENT region!${NC}"
        echo ""
        echo -e "   ${YELLOW}⚠️  Check your F5 configuration!${NC}"
    fi
else
    echo -e "   ${YELLOW}⚠️  Could not find request in any region's logs.${NC}"
    echo ""
    echo "   Possible reasons:"
    echo "   • Log group name is incorrect"
    echo "   • Logs not being captured"
    echo "   • Request ID not logged by app"
    echo ""
    echo "   Try searching manually:"
    echo "   aws logs filter-log-events --log-group-name ${LOG_GROUP} --filter-pattern '${REQUEST_ID}' --region eu-west-2"
fi

echo ""
echo "=============================================="

