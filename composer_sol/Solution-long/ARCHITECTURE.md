# Architecture Overview

## System Design

This health check system verifies that your ECS application is correctly served from the appropriate AWS region based on geolocation routing via an F5 load balancer.

```
┌─────────────────────────────────────────────────────────────┐
│                    F5 Load Balancer                         │
│              (Geolocation Routing)                          │
└──────────────┬──────────────────────────────────────────────┘
               │
               ├─────────────────┬─────────────────┐
               │                 │                 │
               ▼                 ▼                 ▼
    ┌──────────────┐   ┌──────────────┐   ┌──────────────┐
    │  ECS Region  │   │  ECS Region  │   │  ECS Region │
    │  us-east-1  │   │  eu-west-1   │   │ ap-southeast│
    └──────┬───────┘   └──────┬───────┘   └──────┬───────┘
           │                  │                  │
           │                  │                  │
    ┌──────▼───────┐   ┌──────▼───────┐   ┌──────▼───────┐
    │   Lambda     │   │   Lambda     │   │   Lambda     │
    │ Health Check │   │ Health Check │   │ Health Check │
    └──────┬───────┘   └──────┬───────┘   └──────┬───────┘
           │                  │                  │
           └──────────────────┼──────────────────┘
                              │
                    ┌─────────▼──────────┐
                    │  CloudWatch        │
                    │  - Metrics         │
                    │  - Alarms          │
                    │  - Logs            │
                    └─────────┬──────────┘
                              │
                    ┌─────────▼──────────┐
                    │  SNS (Optional)    │
                    │  Email Alerts      │
                    └────────────────────┘
```

## Components

### 1. Lambda Functions (Per Region)

**Purpose**: Periodically check if the application domain is being served from the correct region.

**Location**: Deployed in each AWS region where ECS services run.

**Execution**:
- Scheduled via EventBridge (default: every 5 minutes)
- Can be manually invoked for testing

**Functionality**:
1. Makes HTTP GET request to `https://{app_domain}/health`
2. Extracts region information from:
   - HTTP header: `X-Served-From-Region`
   - JSON response body: `region` or `served_from_region` field
3. Compares detected region with expected region (Lambda's region)
4. Publishes metrics to CloudWatch
5. Returns success/failure status

**Configuration**:
- Environment variables set per region
- Timeout: 30 seconds
- Memory: 256 MB
- Runtime: Python 3.11

### 2. EventBridge Rules

**Purpose**: Schedule Lambda function execution.

**Configuration**:
- Default schedule: `rate(5 minutes)`
- Customizable via Terraform variable `schedule_expression`
- Supports cron expressions for complex schedules

**Example schedules**:
- `rate(5 minutes)` - Every 5 minutes
- `rate(1 hour)` - Every hour
- `cron(0 */6 * * ? *)` - Every 6 hours

### 3. CloudWatch Metrics

**Namespace**: `ECS/HealthCheck`

**Metrics**:
- `HealthCheckStatus`: 1 = success, 0 = failure
- `HealthCheckFailure`: 1 = failure, 0 = success

**Dimensions**:
- `Region`: AWS region code (e.g., us-east-1)
- `Domain`: Application domain name

**Retention**: Standard CloudWatch retention (15 months for custom metrics)

### 4. CloudWatch Alarms

**Purpose**: Alert when health checks fail.

**Configuration**:
- **Alarm Name**: `ecs-health-check-failure-{region}`
- **Metric**: `HealthCheckFailure`
- **Threshold**: > 0 failures
- **Evaluation Periods**: 2 (10 minutes total)
- **Period**: 5 minutes
- **Treat Missing Data**: Breaching (assumes failure if no data)

**Actions**:
- SNS topic notification (if email configured)
- Can be extended to trigger other actions (e.g., PagerDuty, Slack)

### 5. CloudWatch Logs

**Purpose**: Store Lambda execution logs for debugging.

**Configuration**:
- **Log Group**: `/aws/lambda/ecs-health-check-{region}`
- **Retention**: 14 days (configurable)
- **Format**: JSON with execution details

### 6. SNS Topics (Optional)

**Purpose**: Send email alerts when health checks fail.

**Configuration**:
- Created only if `alarm_email` is provided
- Requires email confirmation
- Can be extended to SMS, HTTP endpoints, etc.

## Data Flow

### Normal Operation Flow

1. **EventBridge** triggers Lambda function every 5 minutes
2. **Lambda** makes HTTP request to `https://myapp.kostas.com/health`
3. **F5 Load Balancer** routes request based on Lambda's source IP geolocation
4. **ECS Application** responds with region information
5. **Lambda** verifies region matches expected region
6. **Lambda** publishes success metric to CloudWatch
7. **CloudWatch Alarm** evaluates metrics (no action if healthy)

### Failure Flow

1. **Lambda** detects region mismatch or request failure
2. **Lambda** publishes failure metric to CloudWatch
3. **CloudWatch Alarm** evaluates metrics
4. After 2 consecutive failures (10 minutes):
   - **CloudWatch Alarm** triggers
   - **SNS Topic** sends email alert (if configured)
   - **CloudWatch Logs** contain detailed error information

## Region Verification Methods

The Lambda function supports multiple methods for detecting the serving region:

### Method 1: HTTP Header (Recommended)
```
X-Served-From-Region: us-east-1
```

### Method 2: JSON Response Body
```json
{
  "status": "healthy",
  "region": "us-east-1"
}
```

### Method 3: Alternative Field Names
The Lambda checks for these field names in JSON responses:
- `region`
- `served_from_region`
- `aws_region`
- `deployment_region`

## Security Considerations

### IAM Permissions

Lambda functions use least-privilege IAM roles with permissions for:
- CloudWatch Logs: Create log groups/streams, write logs
- CloudWatch Metrics: Put metric data (namespace-restricted)
- No VPC access (unless configured)
- No access to other AWS services

### Network Security

- Health checks use HTTPS by default
- Lambda functions run in AWS-managed VPC (no customer VPC access)
- No inbound network access required
- Outbound HTTPS only

### Data Privacy

- No sensitive data stored in Lambda environment variables
- Logs contain only health check results (no user data)
- Metrics contain only region and domain information

## Scalability

### Current Limits

- **Lambda**: 1000 concurrent executions per region (default)
- **EventBridge**: 1M invocations/month (free tier)
- **CloudWatch Metrics**: 10 custom metrics (free tier)
- **CloudWatch Logs**: 5GB ingestion/month (free tier)

### Scaling Considerations

- Each region operates independently
- No cross-region dependencies
- Can handle high-frequency checks (up to Lambda concurrency limits)
- CloudWatch metrics scale automatically

## Cost Optimization

### Estimated Monthly Costs (3 regions)

- **Lambda**: ~$0.20/month (5-min schedule, 30s execution)
- **CloudWatch Logs**: ~$0.50/month (14-day retention)
- **CloudWatch Metrics**: Free (within free tier)
- **EventBridge**: Free (within free tier)
- **SNS**: Free (within free tier)

**Total**: ~$2-3/month for 3 regions

### Cost Reduction Tips

1. Increase schedule interval (e.g., `rate(15 minutes)`)
2. Reduce CloudWatch Logs retention (e.g., 7 days)
3. Use CloudWatch Logs Insights instead of storing all logs
4. Consolidate metrics if monitoring multiple domains

## High Availability

### Lambda Availability

- Lambda functions run in multiple Availability Zones automatically
- No single point of failure
- AWS manages infrastructure redundancy

### Monitoring Redundancy

- Each region monitors independently
- Failure in one region doesn't affect others
- CloudWatch alarms provide redundant alerting

## Disaster Recovery

### Lambda Function Recovery

- Functions are stateless
- Can be redeployed quickly via Terraform
- No persistent state to recover

### Monitoring Continuity

- CloudWatch metrics retained for 15 months
- Historical data available for analysis
- Can recreate alarms from Terraform configuration

## Integration Points

### Application Integration

Your ECS application must:
1. Expose `/health` endpoint (or custom path)
2. Include region information in response
3. Set `AWS_REGION` environment variable in task definition

### F5 Load Balancer

- No configuration changes required
- Health checks work with existing geolocation routing
- Verifies routing is working correctly

### AWS Services Integration

- **CloudWatch**: Metrics, alarms, logs
- **EventBridge**: Scheduling
- **SNS**: Alerts (optional)
- **IAM**: Permissions management
- **Lambda**: Function execution

## Monitoring & Observability

### Key Metrics to Monitor

1. **HealthCheckStatus**: Overall health check success rate
2. **HealthCheckFailure**: Failure count and frequency
3. **Lambda Duration**: Execution time trends
4. **Lambda Errors**: Function execution errors

### Dashboards

Create CloudWatch Dashboards to visualize:
- Health check success rate per region
- Failure trends over time
- Regional comparison
- Response time trends

### Alerting Strategy

1. **Immediate Alerts**: Region mismatch detected
2. **Trend Alerts**: Increasing failure rate
3. **Availability Alerts**: No health checks received (missing data)

## Future Enhancements

Potential improvements:
1. **Multi-endpoint checks**: Verify multiple endpoints per region
2. **Response time monitoring**: Track and alert on slow responses
3. **Content verification**: Verify response content matches expected region
4. **Geographic testing**: Use VPN endpoints to test from different locations
5. **Automated remediation**: Trigger actions on failure (e.g., restart ECS tasks)
6. **Dashboard integration**: Pre-built CloudWatch dashboards
7. **Slack/PagerDuty integration**: Additional alert channels

