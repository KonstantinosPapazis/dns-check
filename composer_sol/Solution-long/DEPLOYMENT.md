# Multi-Region Deployment Guide

This guide provides step-by-step instructions for deploying the health check system across multiple AWS regions.

## Prerequisites

1. AWS CLI configured with credentials that have permissions to:
   - Create Lambda functions
   - Create IAM roles and policies
   - Create CloudWatch alarms and EventBridge rules
   - Create SNS topics (if using email alerts)

2. Terraform >= 1.0 installed

3. Your ECS application modified to include region information in health check responses

## Deployment Strategy

Since Terraform doesn't easily support deploying to multiple regions in a single run, we'll deploy to each region separately. Each deployment is independent and can be managed separately.

## Step-by-Step Deployment

### Step 1: Prepare Configuration

1. Copy the example variables file:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

2. Edit `terraform.tfvars` with your values:
   ```hcl
   app_domain = "myapp.kostas.com"
   regions    = ["us-east-1"]  # Deploy one region at a time
   primary_region = "us-east-1"
   alarm_email = "your-email@example.com"
   ```

### Step 2: Build Lambda Package

Build the Lambda deployment package:
```bash
make build
# Or manually:
./scripts/build_lambda.sh
```

This creates `build/lambda_function.zip` (or `lambda_function.zip` in the root).

### Step 3: Deploy to Each Region

For each region, follow these steps:

#### Region 1: us-east-1

```bash
# Set AWS region
export AWS_REGION=us-east-1
export AWS_DEFAULT_REGION=us-east-1

# Update terraform.tfvars to deploy only this region
# Edit terraform.tfvars: regions = ["us-east-1"], primary_region = "us-east-1"

# Initialize Terraform
terraform init

# Review plan
terraform plan -var-file=terraform.tfvars

# Apply
terraform apply -var-file=terraform.tfvars
```

#### Region 2: eu-west-1

```bash
# Set AWS region
export AWS_REGION=eu-west-1
export AWS_DEFAULT_REGION=eu-west-1

# Update terraform.tfvars
# Edit terraform.tfvars: regions = ["eu-west-1"], primary_region = "eu-west-1"

# Reinitialize Terraform (or use a separate directory/workspace)
terraform init -reconfigure

# Review plan
terraform plan -var-file=terraform.tfvars

# Apply
terraform apply -var-file=terraform.tfvars
```

#### Region 3: ap-southeast-1

```bash
# Set AWS region
export AWS_REGION=ap-southeast-1
export AWS_DEFAULT_REGION=ap-southeast-1

# Update terraform.tfvars
# Edit terraform.tfvars: regions = ["ap-southeast-1"], primary_region = "ap-southeast-1"

# Reinitialize Terraform
terraform init -reconfigure

# Review plan
terraform plan -var-file=terraform.tfvars

# Apply
terraform apply -var-file=terraform.tfvars
```

### Alternative: Using Terraform Workspaces

If you prefer to keep everything in one Terraform state with workspaces:

```bash
# Build Lambda package once
make build

# Deploy to each region using workspaces
for region in us-east-1 eu-west-1 ap-southeast-1; do
  echo "Deploying to $region..."
  terraform workspace new $region 2>/dev/null || terraform workspace select $region
  terraform init
  terraform apply \
    -var="regions=[\"$region\"]" \
    -var="primary_region=$region" \
    -var="app_domain=myapp.kostas.com" \
    -var="alarm_email=your-email@example.com"
done
```

### Alternative: Separate Directories

For complete isolation, use separate directories:

```bash
# Build Lambda package
make build

# Copy to each region directory
for region in us-east-1 eu-west-1 ap-southeast-1; do
  mkdir -p deployments/$region
  cp -r *.tf modules/ deployments/$region/
  cp lambda_function.zip deployments/$region/
  
  cd deployments/$region
  terraform init
  terraform apply \
    -var="regions=[\"$region\"]" \
    -var="primary_region=$region" \
    -var="app_domain=myapp.kostas.com" \
    -var="alarm_email=your-email@example.com"
  cd ../..
done
```

## Step 4: Verify Deployment

### Check Lambda Functions

```bash
# For each region
aws lambda list-functions --region us-east-1 \
  --query "Functions[?contains(FunctionName, 'ecs-health-check')].[FunctionName, Runtime, LastModified]"

aws lambda list-functions --region eu-west-1 \
  --query "Functions[?contains(FunctionName, 'ecs-health-check')].[FunctionName, Runtime, LastModified]"

aws lambda list-functions --region ap-southeast-1 \
  --query "Functions[?contains(FunctionName, 'ecs-health-check')].[FunctionName, Runtime, LastModified]"
```

### Test Lambda Functions Manually

```bash
# Test us-east-1
aws lambda invoke \
  --function-name ecs-health-check-us-east-1 \
  --region us-east-1 \
  --payload '{}' \
  response-us-east-1.json
cat response-us-east-1.json

# Test eu-west-1
aws lambda invoke \
  --function-name ecs-health-check-eu-west-1 \
  --region eu-west-1 \
  --payload '{}' \
  response-eu-west-1.json
cat response-eu-west-1.json

# Test ap-southeast-1
aws lambda invoke \
  --function-name ecs-health-check-ap-southeast-1 \
  --region ap-southeast-1 \
  --payload '{}' \
  response-ap-southeast-1.json
cat response-ap-southeast-1.json
```

### Check EventBridge Rules

```bash
aws events list-rules --region us-east-1 \
  --name-prefix ecs-health-check-schedule

aws events list-rules --region eu-west-1 \
  --name-prefix ecs-health-check-schedule

aws events list-rules --region ap-southeast-1 \
  --name-prefix ecs-health-check-schedule
```

### Check CloudWatch Alarms

```bash
aws cloudwatch describe-alarms --region us-east-1 \
  --alarm-name-prefix ecs-health-check-failure

aws cloudwatch describe-alarms --region eu-west-1 \
  --alarm-name-prefix ecs-health-check-failure

aws cloudwatch describe-alarms --region ap-southeast-1 \
  --alarm-name-prefix ecs-health-check-failure
```

### Monitor CloudWatch Metrics

Wait a few minutes after deployment, then check metrics:

```bash
# Get metrics for us-east-1
aws cloudwatch get-metric-statistics \
  --namespace ECS/HealthCheck \
  --metric-name HealthCheckStatus \
  --dimensions Name=Region,Value=us-east-1 Name=Domain,Value=myapp.kostas.com \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum \
  --region us-east-1
```

## Step 5: Subscribe to SNS Alerts (if configured)

If you provided an `alarm_email`, check your email and confirm the SNS subscription:

1. Check your email inbox for a subscription confirmation email from AWS SNS
2. Click the confirmation link
3. Verify subscription status:
   ```bash
   aws sns list-subscriptions-by-topic \
     --topic-arn arn:aws:sns:us-east-1:ACCOUNT_ID:ecs-health-check-alerts-us-east-1 \
     --region us-east-1
   ```

## Troubleshooting Deployment Issues

### Issue: Lambda function fails to create

**Symptoms**: Terraform apply fails with IAM or Lambda errors

**Solutions**:
1. Verify IAM permissions for Lambda creation
2. Check if Lambda function name already exists (may need to delete old version)
3. Verify Lambda ZIP file exists and is valid

### Issue: EventBridge rule not triggering Lambda

**Symptoms**: Lambda function exists but never executes

**Solutions**:
1. Check Lambda permissions for EventBridge:
   ```bash
   aws lambda get-policy \
     --function-name ecs-health-check-us-east-1 \
     --region us-east-1
   ```
2. Verify EventBridge rule target:
   ```bash
   aws events list-targets-by-rule \
     --rule ecs-health-check-schedule-us-east-1 \
     --region us-east-1
   ```

### Issue: CloudWatch metrics not appearing

**Symptoms**: Lambda executes but no metrics in CloudWatch

**Solutions**:
1. Check Lambda logs for errors:
   ```bash
   aws logs tail /aws/lambda/ecs-health-check-us-east-1 --follow --region us-east-1
   ```
2. Verify IAM permissions for CloudWatch PutMetricData
3. Check metric namespace matches: `ECS/HealthCheck`

## Updating Deployment

To update the Lambda function code:

1. Modify `lambda/health_check.py`
2. Rebuild package: `make build`
3. Update Lambda in each region:
   ```bash
   # For each region
   export AWS_REGION=us-east-1
   terraform apply -var-file=terraform.tfvars
   ```

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

Or with workspaces:

```bash
for region in us-east-1 eu-west-1 ap-southeast-1; do
  terraform workspace select $region
  terraform destroy -var-file=terraform.tfvars
done
```

