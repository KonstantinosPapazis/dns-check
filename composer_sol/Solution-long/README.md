# ECS Multi-Region Health Check System

This solution provides automated health checks to verify that your ECS application is being correctly served from the appropriate AWS region based on geolocation routing via an F5 load balancer.

## Architecture Overview

The solution consists of:

1. **Lambda Functions**: Deployed in each region (us-east-1, eu-west-1, ap-southeast-1) that periodically check if the application domain is being served from the correct region
2. **EventBridge Rules**: Schedule the Lambda functions to run at regular intervals (default: every 5 minutes)
3. **CloudWatch Metrics & Alarms**: Monitor health check results and alert on failures
4. **SNS Notifications**: Optional email alerts when health checks fail

## How It Works

1. Each Lambda function makes an HTTP request to your application's health check endpoint (`/health`)
2. The Lambda verifies that the response includes region identification (via header or response body)
3. The Lambda confirms the detected region matches the expected region for that Lambda
4. Results are sent to CloudWatch Metrics
5. CloudWatch Alarms trigger if failures are detected

## Prerequisites

- AWS CLI configured with appropriate credentials
- Terraform >= 1.0 installed
- Python 3.11+ (for local testing)
- Your ECS application must expose a `/health` endpoint that includes region information

## Quick Start

### Step 1: Modify Your Application

Your ECS application needs to include region information in health check responses. See `examples/app_response_example.py` for examples.

**Required**: Add one of the following to your health check endpoint:

- **Option A**: HTTP Header `X-Served-From-Region` with the AWS region code
- **Option B**: JSON response body with a `region` or `served_from_region` field

Example response:
```json
{
  "status": "healthy",
  "region": "us-east-1",
  "timestamp": "2024-01-15T10:30:00Z"
}
```

**Important**: Set the `AWS_REGION` environment variable in your ECS task definition for each region deployment.

### Step 2: Configure Variables

1. Copy `terraform.tfvars.example` to `terraform.tfvars`:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

2. Edit `terraform.tfvars` with your values:
   ```hcl
   app_domain = "myapp.kostas.com"
   regions    = ["us-east-1", "eu-west-1", "ap-southeast-1"]
   alarm_email = "your-email@example.com"
   ```

### Step 3: Deploy Infrastructure

#### Option A: Deploy to All Regions from One Place

Since Terraform doesn't easily support multi-region deployments in a single run, you have two options:

**Option 1: Deploy separately to each region**

```bash
# For each region, set AWS_REGION and deploy
export AWS_REGION=us-east-1
terraform init
terraform plan -var="regions=[\"us-east-1\"]" -var="primary_region=us-east-1"
terraform apply

export AWS_REGION=eu-west-1
terraform init -reconfigure
terraform plan -var="regions=[\"eu-west-1\"]" -var="primary_region=eu-west-1"
terraform apply

export AWS_REGION=ap-southeast-1
terraform init -reconfigure
terraform plan -var="regions=[\"ap-southeast-1\"]" -var="primary_region=ap-southeast-1"
terraform apply
```

**Option 2: Use separate Terraform workspaces per region**

```bash
# Create and deploy to each region workspace
for region in us-east-1 eu-west-1 ap-southeast-1; do
  terraform workspace new $region || terraform workspace select $region
  terraform init
  terraform apply -var="regions=[\"$region\"]" -var="primary_region=$region"
done
```

#### Option B: Use AWS Organizations/Cross-Account (Advanced)

If you have multiple AWS accounts per region, configure provider aliases in `main.tf` and use assume roles.

### Step 4: Verify Deployment

1. Check Lambda functions are created:
   ```bash
   aws lambda list-functions --region us-east-1 --query "Functions[?contains(FunctionName, 'ecs-health-check')]"
   ```

2. Test a Lambda function manually:
   ```bash
   aws lambda invoke \
     --function-name ecs-health-check-us-east-1 \
     --region us-east-1 \
     response.json
   cat response.json
   ```

3. Check CloudWatch Metrics:
   ```bash
   aws cloudwatch get-metric-statistics \
     --namespace ECS/HealthCheck \
     --metric-name HealthCheckStatus \
     --dimensions Name=Region,Value=us-east-1 Name=Domain,Value=myapp.kostas.com \
     --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
     --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
     --period 300 \
     --statistics Sum
   ```

## Configuration Options

### Environment Variables (Lambda)

- `APP_DOMAIN`: Application domain name (default: `myapp.kostas.com`)
- `AWS_REGION`: Automatically set by Lambda runtime
- `HEALTH_CHECK_PATH`: Health check endpoint path (default: `/health`)
- `REGION_HEADER`: Header name for region info (default: `X-Served-From-Region`)
- `USE_HTTPS`: Use HTTPS for requests (default: `true`)

### Terraform Variables

- `app_domain`: Your application domain
- `regions`: List of AWS regions to deploy to
- `schedule_expression`: CloudWatch Events schedule (default: `rate(5 minutes)`)
- `alarm_email`: Email for CloudWatch alarms (optional)
- `health_check_path`: Health check endpoint path
- `region_header`: HTTP header name for region

## Testing from Different Geographic Locations

**Challenge**: Lambda functions run in specific AWS regions, but F5 routes based on source IP geolocation. To test geolocation routing:

### Option 1: Use VPN Endpoints

Deploy VPN endpoints in different regions and route Lambda traffic through them (requires VPC configuration).

### Option 2: Use Third-Party Services

Use services like:
- **AWS Global Accelerator** with endpoints in each region
- **Third-party monitoring tools** (Datadog, New Relic, etc.) with global test locations
- **AWS Device Farm** or similar for geographic testing

### Option 3: Application-Level Verification

The best approach is to ensure your application includes region information in responses, and verify:
1. Lambda in Region A receives responses indicating Region A
2. Lambda in Region B receives responses indicating Region B
3. This confirms F5 is routing correctly based on Lambda's source IP

## Monitoring & Alerts

### CloudWatch Metrics

Metrics are published to namespace `ECS/HealthCheck`:

- `HealthCheckStatus`: 1 = success, 0 = failure
- `HealthCheckFailure`: 1 = failure, 0 = success

Dimensions:
- `Region`: AWS region code
- `Domain`: Application domain name

### CloudWatch Alarms

Alarms are created automatically:
- **Name**: `ecs-health-check-failure-{region}`
- **Trigger**: When `HealthCheckFailure` > 0 for 2 consecutive periods (10 minutes)
- **Action**: Sends email via SNS (if `alarm_email` is configured)

### Viewing Logs

```bash
# View Lambda logs
aws logs tail /aws/lambda/ecs-health-check-us-east-1 --follow --region us-east-1
```

## Troubleshooting

### Lambda Function Fails

1. Check CloudWatch Logs for the Lambda function
2. Verify the application domain is accessible from the Lambda's region
3. Ensure the health check endpoint returns region information
4. Check IAM permissions for CloudWatch Metrics

### Region Mismatch Detected

1. Verify your application is correctly setting the region in responses
2. Check F5 load balancer configuration
3. Verify ECS task definitions have `AWS_REGION` environment variable set
4. Test the health endpoint manually:
   ```bash
   curl -H "X-Served-From-Region: us-east-1" https://myapp.kostas.com/health
   ```

### No Metrics Appearing

1. Verify Lambda function is executing (check logs)
2. Check IAM permissions for `cloudwatch:PutMetricData`
3. Ensure metric namespace matches: `ECS/HealthCheck`

## Cost Estimation

- **Lambda**: ~$0.20/month per function (assuming 5-minute schedule)
- **CloudWatch Logs**: ~$0.50/month per function (14-day retention)
- **CloudWatch Metrics**: Included in free tier (first 10 custom metrics)
- **EventBridge**: Free (first 1 million invocations/month)
- **SNS**: Free (first 1 million publishes/month)

**Total**: ~$2-3/month for 3 regions

## Security Considerations

1. **IAM Roles**: Lambda functions use least-privilege IAM roles
2. **VPC**: If your application is in a VPC, configure Lambda VPC settings
3. **HTTPS**: Health checks use HTTPS by default
4. **Secrets**: No sensitive data is stored in Lambda environment variables

## Cleanup

To remove all resources:

```bash
# For each region
export AWS_REGION=us-east-1
terraform destroy -var-file=terraform.tfvars

export AWS_REGION=eu-west-1
terraform destroy -var-file=terraform.tfvars

export AWS_REGION=ap-southeast-1
terraform destroy -var-file=terraform.tfvars
```

## Additional Resources

- [AWS Lambda Documentation](https://docs.aws.amazon.com/lambda/)
- [CloudWatch Events Documentation](https://docs.aws.amazon.com/eventbridge/)
- [ECS Task Definition Environment Variables](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/taskdef-env-vars.html)

## Support

For issues or questions:
1. Check CloudWatch Logs for detailed error messages
2. Review the Lambda function code in `lambda/health_check.py`
3. Verify your application's health check endpoint format matches expectations

