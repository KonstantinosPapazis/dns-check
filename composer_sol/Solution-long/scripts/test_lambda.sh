#!/bin/bash
# Test script to manually invoke Lambda functions and verify health checks

set -e

REGIONS=("us-east-1" "eu-west-1" "ap-southeast-1")
APP_DOMAIN="${APP_DOMAIN:-myapp.kostas.com}"

echo "Testing ECS Health Check Lambda Functions"
echo "=========================================="
echo "App Domain: $APP_DOMAIN"
echo ""

for region in "${REGIONS[@]}"; do
    echo "Testing region: $region"
    echo "----------------------"
    
    function_name="ecs-health-check-${region}"
    
    # Check if function exists
    if ! aws lambda get-function --function-name "$function_name" --region "$region" &>/dev/null; then
        echo "  ❌ Lambda function not found: $function_name"
        echo ""
        continue
    fi
    
    echo "  ✓ Function exists: $function_name"
    
    # Invoke function
    echo "  Invoking function..."
    response_file=$(mktemp)
    
    if aws lambda invoke \
        --function-name "$function_name" \
        --region "$region" \
        --payload '{}' \
        "$response_file" &>/dev/null; then
        
        # Parse response
        status_code=$(jq -r '.statusCode' "$response_file" 2>/dev/null || echo "unknown")
        body=$(jq -r '.body' "$response_file" 2>/dev/null || cat "$response_file")
        
        echo "  Status Code: $status_code"
        
        # Extract key information
        if echo "$body" | jq -e '.result' &>/dev/null; then
            result=$(echo "$body" | jq -r '.result')
            region_match=$(echo "$result" | jq -r '.region_match // "unknown"')
            detected_region=$(echo "$result" | jq -r '.detected_region // "unknown"')
            expected_region=$(echo "$result" | jq -r '.expected_region // "unknown"')
            
            echo "  Expected Region: $expected_region"
            echo "  Detected Region: $detected_region"
            echo "  Region Match: $region_match"
            
            if [ "$region_match" = "true" ]; then
                echo "  ✅ Health check PASSED"
            else
                echo "  ❌ Health check FAILED - Region mismatch!"
            fi
        else
            echo "  Response: $body"
        fi
        
        rm -f "$response_file"
    else
        echo "  ❌ Failed to invoke function"
        rm -f "$response_file"
    fi
    
    echo ""
done

echo "Test Summary"
echo "============"
echo "Check CloudWatch Logs for detailed execution logs:"
for region in "${REGIONS[@]}"; do
    echo "  $region: aws logs tail /aws/lambda/ecs-health-check-${region} --follow --region ${region}"
done

