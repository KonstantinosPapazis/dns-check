# DNS Geolocation Routing Checker 🌍

A solution to validate that your F5 load balancer is correctly routing users to the appropriate regional ECS clusters based on geolocation.

## Problem

You have:
- **ECS services** deployed in 3 AWS regions
- **F5 load balancer** performing geolocation-based routing
- **Need to verify** that `myapp.kostas.com` routes users to the correct regional backend

## Solution Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           F5 Load Balancer                              │
│                     (Geolocation-based routing)                         │
│                        myapp.kostas.com                                 │
└────────────────────────────────┬────────────────────────────────────────┘
                                 │
        ┌────────────────────────┼────────────────────────┐
        │                        │                        │
        ▼                        ▼                        ▼
┌───────────────┐      ┌───────────────┐      ┌───────────────┐
│  us-east-1    │      │  eu-west-1    │      │ ap-southeast-1│
│  ECS Cluster  │      │  ECS Cluster  │      │  ECS Cluster  │
└───────────────┘      └───────────────┘      └───────────────┘
        ▲                        ▲                        ▲
        │                        │                        │
        │    DNS Check Lambda    │                        │
        │    (validates route)   │                        │
        │                        │                        │
┌───────────────┐      ┌───────────────┐      ┌───────────────┐
│    Lambda     │      │    Lambda     │      │    Lambda     │
│  us-east-1    │      │  eu-west-1    │      │ ap-southeast-1│
│               │      │               │      │               │
│ "Am I being   │      │ "Am I being   │      │ "Am I being   │
│  routed to    │      │  routed to    │      │  routed to    │
│  us-east-1?"  │      │  eu-west-1?"  │      │  ap-southeast │
└───────────────┘      └───────────────┘      └───────────────┘
        │                        │                        │
        └────────────────────────┼────────────────────────┘
                                 │
                                 ▼
                    ┌───────────────────────┐
                    │  CloudWatch Metrics   │
                    │  & Alarms             │
                    └───────────────────────┘
```

## How It Works

1. **Lambda Probe**: A Lambda function runs in each region on a schedule (default: every 5 minutes)

2. **Region Validation**: Each Lambda:
   - Makes an HTTP request to `myapp.kostas.com/health`
   - The F5 routes based on the Lambda's IP (which is regional)
   - The ECS app responds with its region (via header or JSON body)
   - Lambda validates: "Did I reach the ECS in my region?"

3. **Metrics & Alarms**: Results are published to CloudWatch with alarms for routing failures

## Prerequisites

### 1. ECS Application Must Expose Region Information

Your ECS application needs to return which region it's running in. Choose one method:

**Option A: HTTP Header (Recommended)**
```python
# Add to your application responses
response.headers['X-Served-By-Region'] = os.environ.get('AWS_REGION')
```

**Option B: JSON Response Body**
```json
{
  "status": "healthy",
  "region": "eu-west-1"
}
```

See `ecs-app-example/health_endpoint.py` for implementation examples.

### 2. AWS Credentials

Ensure you have AWS credentials configured with permissions to:
- Create Lambda functions
- Create IAM roles
- Create CloudWatch resources
- Deploy to multiple regions

## Quick Start

### 1. Clone and Configure

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:
```hcl
target_domain   = "myapp.kostas.com"
health_endpoint = "/health"
region_header   = "X-Served-By-Region"

regions = {
  "us-east-1" = {
    expected_region = "us-east-1"
    enabled         = true
  }
  "eu-west-1" = {
    expected_region = "eu-west-1"
    enabled         = true
  }
  "ap-southeast-1" = {
    expected_region = "ap-southeast-1"
    enabled         = true
  }
}
```

### 2. Deploy

```bash
terraform init
terraform plan
terraform apply
```

### 3. Verify

Manually invoke a Lambda to test:
```bash
aws lambda invoke \
  --function-name dns-check-us-east-1 \
  --region us-east-1 \
  response.json

cat response.json
```

## Configuration Options

| Variable | Description | Default |
|----------|-------------|---------|
| `target_domain` | Domain to check | - (required) |
| `health_endpoint` | Health check path | `/health` |
| `region_header` | HTTP header with region | `X-Served-By-Region` |
| `schedule_expression` | Check frequency | `rate(5 minutes)` |
| `alarm_enabled` | Create CloudWatch alarms | `true` |
| `alarm_sns_topic_arn` | SNS topic for alerts | `""` |

## CloudWatch Metrics

Metrics are published to namespace: `DNS-Check/Geolocation`

| Metric | Description |
|--------|-------------|
| `DNSResolutionSuccess` | DNS lookup succeeded |
| `HTTPCheckSuccess` | HTTP request succeeded |
| `RegionMatchSuccess` | Response came from expected region |
| `GeolocationRoutingFailure` | Routing mismatch detected (for easy alarming) |

### Dimensions
- `Domain`: The target domain
- `ProbeRegion`: Region where the Lambda ran

## Alarms

Two CloudWatch alarms are created per region:

1. **Routing Failure**: Triggers when requests are routed to wrong region
2. **HTTP Failure**: Triggers when health endpoint is unreachable

## Dashboard

A CloudWatch dashboard is automatically created showing:
- Region match success rates
- Routing failures over time
- HTTP check status
- DNS resolution status
- Recent check logs

Access at: CloudWatch → Dashboards → `dns-check-geolocation-monitoring`

## Troubleshooting

### "Could not determine served region from response"

Your ECS app isn't returning region information. Ensure either:
- The `X-Served-By-Region` header is set, OR
- The JSON response contains a `region` field

### Lambda times out

- Check if your ECS endpoint is accessible from Lambda IPs
- Verify security groups allow traffic
- Increase `timeout_seconds` if needed

### All regions show routing failures

- Verify the F5 is configured correctly for geolocation routing
- Check if F5 can identify AWS Lambda IPs correctly
- Lambda IPs might be in IP ranges that F5 associates with a different region

### DNS resolution fails

- Verify the domain is correctly configured
- Check if Lambda has internet access (needs NAT gateway if in VPC)

## Alternative Approaches

### CloudWatch Synthetics

AWS-native synthetic monitoring with canary scripts:
```python
# Can run from multiple regions with browser-like testing
```
**Pros**: No infrastructure to manage, visual workflow capture
**Cons**: Higher cost, less control

### Third-Party Services

- **Datadog Synthetic Monitoring**: Probes from 50+ global locations
- **Pingdom**: Simple uptime + geolocation testing
- **Catchpoint**: Enterprise-grade synthetic monitoring

**Pros**: Global coverage beyond AWS regions
**Cons**: Additional cost, external dependency

### Route 53 Health Checks

If you migrate from F5 to Route 53:
```hcl
resource "aws_route53_health_check" "regional" {
  fqdn              = "myapp.kostas.com"
  type              = "HTTPS"
  resource_path     = "/health"
  regions           = ["us-east-1", "eu-west-1", "ap-southeast-1"]
}
```

## Project Structure

```
dns-check/
├── lambda/
│   └── dns_check.py           # Lambda function code
├── terraform/
│   ├── main.tf                # Main Terraform config
│   ├── variables.tf           # Input variables
│   ├── outputs.tf             # Output values
│   ├── dashboard.tf           # CloudWatch dashboard
│   ├── terraform.tfvars.example
│   └── modules/
│       └── regional-lambda/   # Reusable regional deployment
│           ├── main.tf
│           ├── variables.tf
│           └── outputs.tf
├── ecs-app-example/
│   └── health_endpoint.py     # Example ECS app integration
└── README.md
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

## License

MIT License - feel free to use and modify for your needs.
