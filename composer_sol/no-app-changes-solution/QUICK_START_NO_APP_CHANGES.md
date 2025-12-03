# Quick Start - No Application Changes Required

Get your ECS health check system running **without modifying your application code** in 5 minutes.

## Prerequisites

- [x] AWS CLI configured
- [x] Terraform installed
- [x] Application domain accessible (e.g., `myapp.kostas.com`)
- [x] **No application code changes needed!**

## Step 1: Fetch AWS IP Ranges (2 minutes)

Update the Lambda function with latest AWS IP ranges for better accuracy:

```bash
# Generate updated IP ranges
python3 scripts/fetch_aws_ip_ranges.py > aws_ip_ranges.py

# Review the output and update lambda/health_check_no_app_changes.py
# Replace AWS_REGION_IP_PREFIXES with the generated dictionary
```

**Optional but recommended** for better accuracy.

## Step 2: Configure (1 minute)

```bash
# Copy and edit configuration
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your domain and email
```

## Step 3: Build Lambda Package (1 minute)

```bash
# Build the Lambda package
mkdir -p lambda_package
cp lambda/health_check_no_app_changes.py lambda_package/
cp lambda/requirements_no_app_changes.txt lambda_package/requirements.txt

# Or use Terraform which will do this automatically
terraform init
```

## Step 4: Deploy to First Region (2 minutes)

```bash
# Use the no-app-changes Terraform configuration
export AWS_REGION=us-east-1

# Initialize Terraform
terraform init

# Use the no-app-changes main file
terraform apply \
  -var-file=terraform.tfvars \
  -var="regions=[\"us-east-1\"]" \
  -var="primary_region=us-east-1"
```

**Note:** Update `terraform.tfvars` to deploy one region at a time:
```hcl
regions = ["us-east-1"]  # Change this for each region
```

## Step 5: Repeat for Other Regions

```bash
# Region 2
export AWS_REGION=eu-west-1
terraform apply \
  -var-file=terraform.tfvars \
  -var="regions=[\"eu-west-1\"]" \
  -var="primary_region=eu-west-1"

# Region 3
export AWS_REGION=ap-southeast-1
terraform apply \
  -var-file=terraform.tfvars \
  -var="regions=[\"ap-southeast-1\"]" \
  -var="primary_region=ap-southeast-1"
```

## Step 6: Test (1 minute)

```bash
# Test manually
aws lambda invoke \
  --function-name ecs-health-check-no-app-changes-us-east-1 \
  --region us-east-1 \
  --payload '{}' \
  response.json

cat response.json | jq '.'
```

## Step 7: Calibrate Latency Ranges (5 minutes)

After initial deployment, measure actual latencies and update the Lambda function:

1. **Run multiple tests:**
   ```bash
   for i in {1..10}; do
     aws lambda invoke \
       --function-name ecs-health-check-no-app-changes-us-east-1 \
       --region us-east-1 \
       --payload '{}' \
       response-$i.json
   done
   ```

2. **Extract latency measurements:**
   ```bash
   grep -h "average_latency_ms" response-*.json | jq -r '.result.verification_methods.latency.average_latency_ms'
   ```

3. **Update Lambda function:**
   Edit `lambda/health_check_no_app_changes.py` and update `EXPECTED_LATENCY_RANGES`:
   ```python
   EXPECTED_LATENCY_RANGES = {
       'us-east-1': (min_latency, max_latency),  # Your measured values
       'eu-west-1': (min_latency, max_latency),
       'ap-southeast-1': (min_latency, max_latency),
   }
   ```

4. **Redeploy:**
   ```bash
   terraform apply -var-file=terraform.tfvars
   ```

## Understanding Results

### Success Response
```json
{
  "statusCode": 200,
  "body": {
    "message": "Health check passed",
    "result": {
      "overall_match": true,
      "confidence": "high",
      "score": 0.9,
      "verification_methods": {
        "dns_ip_geolocation": { "match": true },
        "http_response": { "ip_match": true },
        "latency": { "match": true }
      }
    }
  }
}
```

### Failure Response
```json
{
  "statusCode": 500,
  "body": {
    "message": "Health check failed - region verification failed",
    "result": {
      "overall_match": false,
      "confidence": "low",
      "score": 0.3,
      "reason": "DNS IP does not match expected region; Response IP does not match expected region"
    }
  }
}
```

## Confidence Levels

- **High (≥70%)**: Very likely correct region
- **Medium (40-69%)**: Probably correct region
- **Low (<40%)**: Uncertain, may need investigation

## Monitoring

### CloudWatch Metrics
- **HealthCheckStatus**: 1 = pass, 0 = fail
- **HealthCheckConfidence**: Score 0-1

### CloudWatch Logs
```bash
aws logs tail /aws/lambda/ecs-health-check-no-app-changes-us-east-1 --follow
```

### CloudWatch Alarms
Alarms trigger when confidence drops below 50% for 2 consecutive periods.

## Improving Accuracy

### Option 1: Configure F5 Headers (Best)
If you can configure F5, add a custom header:
```
X-Served-From-Region: us-east-1
```
This improves accuracy to 85-95%.

### Option 2: Update AWS IP Ranges
Run monthly to get latest AWS IP ranges:
```bash
python3 scripts/fetch_aws_ip_ranges.py
```

### Option 3: Fine-tune Latency Ranges
After measuring actual latencies, update `EXPECTED_LATENCY_RANGES` in the Lambda function.

## Troubleshooting

### Low Confidence Scores

**Problem:** Confidence score consistently low

**Solutions:**
1. Check DNS resolution: `nslookup myapp.kostas.com`
2. Verify AWS IP ranges are up to date
3. Calibrate latency ranges
4. Consider configuring F5 headers

### False Positives

**Problem:** System reports wrong region

**Solutions:**
1. Check if using CDN (CDN IPs may not match region)
2. Verify DNS resolves to correct IPs
3. Review CloudWatch logs for details
4. Adjust confidence threshold if needed

## Next Steps

1. ✅ Deploy and test
2. ✅ Calibrate latency ranges
3. ✅ Monitor confidence scores
4. 🔄 Consider configuring F5 headers (if possible)
5. 🔄 Plan migration to "with app changes" solution (long-term)

## See Also

- `README_NO_APP_CHANGES.md` - Detailed documentation
- `COMPARISON.md` - Compare with app changes solution
- `README.md` - Original solution with app changes

