# Quick Start Guide

Get your ECS health check system up and running in 5 minutes.

## Prerequisites Checklist

- [ ] AWS CLI configured (`aws configure`)
- [ ] Terraform installed (`terraform version`)
- [ ] ECS application modified to include region in `/health` endpoint
- [ ] Application domain accessible (e.g., `myapp.kostas.com`)

## 1. Modify Your Application (5 minutes)

Add region information to your health check endpoint. Choose one method:

### Method A: HTTP Header (Recommended)
```python
# In your /health endpoint
response.headers['X-Served-From-Region'] = os.environ.get('AWS_REGION')
```

### Method B: JSON Response
```python
# In your /health endpoint
return jsonify({
    'status': 'healthy',
    'region': os.environ.get('AWS_REGION')
})
```

**Important**: Set `AWS_REGION` environment variable in your ECS task definition for each region.

## 2. Configure (2 minutes)

```bash
# Copy and edit configuration
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your domain and email
```

## 3. Build Lambda Package (1 minute)

```bash
make build
# Or: ./scripts/build_lambda.sh
```

## 4. Deploy to First Region (2 minutes)

```bash
export AWS_REGION=us-east-1
terraform init
terraform apply -var-file=terraform.tfvars
```

**Note**: Update `terraform.tfvars` to deploy one region at a time:
```hcl
regions = ["us-east-1"]  # Change this for each region
```

## 5. Repeat for Other Regions

```bash
# Region 2
export AWS_REGION=eu-west-1
terraform init -reconfigure
terraform apply -var-file=terraform.tfvars

# Region 3
export AWS_REGION=ap-southeast-1
terraform init -reconfigure
terraform apply -var-file=terraform.tfvars
```

## 6. Test (1 minute)

```bash
# Test all regions
./scripts/test_lambda.sh

# Or test manually
aws lambda invoke \
  --function-name ecs-health-check-us-east-1 \
  --region us-east-1 \
  --payload '{}' \
  response.json
cat response.json
```

## 7. Monitor

- **CloudWatch Logs**: `/aws/lambda/ecs-health-check-{region}`
- **CloudWatch Metrics**: Namespace `ECS/HealthCheck`
- **CloudWatch Alarms**: `ecs-health-check-failure-{region}`

## Verify It's Working

1. Wait 5-10 minutes for scheduled executions
2. Check CloudWatch Metrics:
   ```bash
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
3. Check Lambda logs for any errors

## Troubleshooting

**Lambda fails**: Check CloudWatch Logs for the function
**Region mismatch**: Verify your app returns correct region in `/health` endpoint
**No metrics**: Check IAM permissions for CloudWatch PutMetricData

## Next Steps

- Review `README.md` for detailed documentation
- Check `DEPLOYMENT.md` for advanced deployment strategies
- See `examples/app_response_example.py` for application integration examples

