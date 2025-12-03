# DNS Geolocation Verification Commands

---

## ⭐ DEFINITIVE TEST (100% Proof)

The ONLY way to be 100% certain which region handles your request:

### Option A: Log-Based Proof (Recommended)

```bash
# 1. Generate unique ID
REQUEST_ID="test-$(date +%s)-$RANDOM"
echo "Request ID: $REQUEST_ID"

# 2. Make request with that ID
curl -sS -H "X-Request-ID: $REQUEST_ID" https://myapp.kostas.com > /dev/null

# 3. Wait for logs
sleep 10

# 4. Search EACH region's logs - only ONE will have it
aws logs filter-log-events --log-group-name /ecs/YOUR-SERVICE --filter-pattern "$REQUEST_ID" --region eu-west-2
aws logs filter-log-events --log-group-name /ecs/YOUR-SERVICE --filter-pattern "$REQUEST_ID" --region ap-southeast-1
aws logs filter-log-events --log-group-name /ecs/YOUR-SERVICE --filter-pattern "$REQUEST_ID" --region us-east-1
```

**The region that has the log entry = the region that handled your request!**

### Option B: Ask F5 Team to Add Header

Have them add an iRule:
```tcl
when HTTP_RESPONSE {
    HTTP::header insert "X-Served-By-Pool" [LB::server pool]
}
```

Then verify:
```bash
curl -sI https://myapp.kostas.com | grep -i "x-served"
```

### Option C: Temporary App Fix (2 lines of code)

Ask devs to add:
```python
response.headers['X-Region'] = os.environ.get('AWS_REGION')
```

Then verify:
```bash
curl -sI https://myapp.kostas.com | grep -i "x-region"
```

---

## Quick IP Check

```bash
# Get the IP you connect to
curl -s -o /dev/null -w "%{remote_ip}\n" https://myapp.kostas.com

# DNS lookup
dig +short myapp.kostas.com

# Reverse lookup (find which region an IP belongs to)
nslookup 10.5.199.143
```

## Connection Info + Timing

```bash
# IP + response time
curl -s -o /dev/null -w "IP: %{remote_ip}\nTime: %{time_total}s\nConnect: %{time_connect}s\n" https://myapp.kostas.com

# Full timing breakdown
curl -sS -w '\nDNS: %{time_namelookup}s\nConnect: %{time_connect}s\nSSL: %{time_appconnect}s\nTotal: %{time_total}s\n' -o /dev/null https://myapp.kostas.com
```

## Response Headers

```bash
# Check for any region/server headers
curl -sI https://myapp.kostas.com | grep -iE "^(server|x-|via):"
```

## IP Geolocation

```bash
# Get IP and lookup its location
curl -s -o /dev/null -w "%{remote_ip}" https://myapp.kostas.com | xargs -I{} curl -s ip-api.com/{}

# Or in two steps
IP=$(curl -s -o /dev/null -w "%{remote_ip}" https://myapp.kostas.com)
echo "IP: $IP"
curl -s "ip-api.com/$IP?fields=country,regionName,city,org"
```

---

## Verification Methods

### 1. Check Response Content

```bash
# See if app returns any identifying info
curl -sS https://myapp.kostas.com | head -50
```

### 2. CloudWatch Metrics (ECS request count per region)

```bash
# Check eu-west-2
aws cloudwatch get-metric-statistics \
  --namespace AWS/ECS \
  --metric-name RequestCount \
  --dimensions Name=ServiceName,Value=YOUR_SERVICE_NAME \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 300 \
  --statistics Sum \
  --region eu-west-2
```

### 3. Watch ECS Logs (see which region processes request)

**Terminal 1 - Watch eu-west-2 logs:**
```bash
aws logs tail /ecs/your-service --follow --region eu-west-2
```

**Terminal 2 - Watch ap-southeast-1 logs:**
```bash
aws logs tail /ecs/your-service --follow --region ap-southeast-1
```

**Terminal 3 - Make the request:**
```bash
curl https://myapp.kostas.com
```

### 4. Request ID Tracing

```bash
# Make request with unique ID
REQUEST_ID="test-$(date +%s)"
echo "Request ID: $REQUEST_ID"
curl -sS -H "X-Request-ID: $REQUEST_ID" https://myapp.kostas.com > /dev/null

# Search logs in each region for that ID
aws logs filter-log-events \
  --log-group-name /ecs/your-service \
  --filter-pattern "$REQUEST_ID" \
  --region eu-west-2

aws logs filter-log-events \
  --log-group-name /ecs/your-service \
  --filter-pattern "$REQUEST_ID" \
  --region ap-southeast-1
```

### 5. Check VPC CIDRs Across All Regions

```bash
for region in us-east-1 eu-west-1 eu-west-2 ap-southeast-1; do
  echo "=== $region ==="
  aws ec2 describe-vpcs --region $region --query 'Vpcs[*].[VpcId,CidrBlock,Tags[?Key==`Name`].Value|[0]]' --output table 2>/dev/null
done
```

### 6. Find Which Region Owns an IP

```bash
# Check all regions for a specific private IP
IP="10.5.199.143"
for region in us-east-1 eu-west-1 eu-west-2 ap-southeast-1 ap-southeast-2; do
  RESULT=$(aws ec2 describe-network-interfaces \
    --filters "Name=addresses.private-ip-address,Values=$IP" \
    --region $region \
    --query 'NetworkInterfaces[*].[Description,AvailabilityZone]' \
    --output text 2>/dev/null)
  if [ -n "$RESULT" ]; then
    echo "Found in $region: $RESULT"
  fi
done
```

### 7. Check ALB/Target Group Health

```bash
aws elbv2 describe-target-health \
  --target-group-arn YOUR_TG_ARN \
  --region eu-west-2
```

---

## All-in-One Regional Test

Run from each CloudShell region:

```bash
echo "========================================"
echo "Region: ${AWS_REGION:-$(curl -s http://169.254.169.254/latest/meta-data/placement/region)}"
echo "========================================"
IP=$(curl -s -o /dev/null -w "%{remote_ip}" https://myapp.kostas.com)
TIME=$(curl -s -o /dev/null -w "%{time_connect}" https://myapp.kostas.com)
echo "Connected to: $IP"
echo "Connect time: ${TIME}s"
echo ""
echo "Reverse DNS:"
nslookup $IP 2>/dev/null | grep -i "name"
echo ""
echo "IP Location:"
curl -s "ip-api.com/$IP?fields=country,regionName,city,org" 2>/dev/null | tr ',' '\n'
echo "========================================"
```

---

---

## ECS Container-Specific Checks

### 1. Get Container Metadata (Region, Cluster, Task ID)

```bash
# ECS Task Metadata v4 (Fargate & EC2)
curl -s ${ECS_CONTAINER_METADATA_URI_V4}/task | jq '{
  cluster: .Cluster,
  taskArn: .TaskARN,
  family: .Family,
  availabilityZone: .AvailabilityZone
}'

# Just the AZ (contains region)
curl -s ${ECS_CONTAINER_METADATA_URI_V4}/task | jq -r '.AvailabilityZone'
```

### 2. Check Environment Variables

```bash
# Region info
echo "AWS_REGION: $AWS_REGION"
echo "AWS_DEFAULT_REGION: $AWS_DEFAULT_REGION"
echo "ECS_CLUSTER: $ECS_CLUSTER"

# All ECS-related env vars
env | grep -iE "^(AWS_|ECS_)" | sort
```

### 3. Container's Own IP (for comparison)

```bash
# Container's private IP
hostname -I

# Or from metadata
curl -s ${ECS_CONTAINER_METADATA_URI_V4} | jq -r '.Networks[0].IPv4Addresses[0]'
```

### 4. What Public IP Does This Container Use?

```bash
# What IP does the internet see when this container makes requests?
curl -s ifconfig.me
curl -s ipinfo.io
curl -s checkip.amazonaws.com
```

### 5. DNS Resolution Details

```bash
# What DNS servers is the container using?
cat /etc/resolv.conf

# Detailed DNS resolution for your app
dig myapp.kostas.com +trace

# Compare resolution from different DNS servers
dig @169.254.169.253 myapp.kostas.com  # VPC DNS resolver
dig @8.8.8.8 myapp.kostas.com           # Google DNS
```

### 6. Network Path to Target

```bash
# Traceroute to see network hops
traceroute myapp.kostas.com

# Or if traceroute not available
mtr -r -c 5 myapp.kostas.com

# TCP traceroute (often better through firewalls)
traceroute -T -p 443 myapp.kostas.com
```

### 7. Full Container Network Info

```bash
# All network interfaces
ip addr

# Routing table
ip route

# Active connections
netstat -tuln 2>/dev/null || ss -tuln
```

### 8. Complete ECS Task Metadata Dump

```bash
# Full task metadata (lots of useful info)
curl -s ${ECS_CONTAINER_METADATA_URI_V4}/task | jq .

# Task stats (CPU, memory, network)
curl -s ${ECS_CONTAINER_METADATA_URI_V4}/task/stats | jq .
```

### 9. Instance Identity (EC2-backed ECS only)

```bash
# If running on EC2 (not Fargate)
curl -s http://169.254.169.254/latest/dynamic/instance-identity/document | jq '{
  region: .region,
  availabilityZone: .availabilityZone,
  instanceId: .instanceId,
  privateIp: .privateIp
}'
```

### 10. All-in-One ECS Container Diagnostic

```bash
echo "=========================================="
echo "ECS CONTAINER DIAGNOSTIC"
echo "=========================================="
echo ""
echo "📍 Container Location:"
echo "   Region: ${AWS_REGION:-$(curl -s ${ECS_CONTAINER_METADATA_URI_V4}/task | jq -r '.AvailabilityZone' | sed 's/[a-z]$//')}"
echo "   AZ: $(curl -s ${ECS_CONTAINER_METADATA_URI_V4}/task 2>/dev/null | jq -r '.AvailabilityZone')"
echo "   Container IP: $(hostname -I | awk '{print $1}')"
echo "   Public IP: $(curl -s checkip.amazonaws.com)"
echo ""
echo "🔗 Target Check (myapp.kostas.com):"
TARGET_IP=$(curl -s -o /dev/null -w "%{remote_ip}" https://myapp.kostas.com)
echo "   Resolved to: $TARGET_IP"
echo "   Reverse DNS: $(nslookup $TARGET_IP 2>/dev/null | grep 'name =' | awk '{print $NF}')"
echo "   Connect time: $(curl -s -o /dev/null -w "%{time_connect}s" https://myapp.kostas.com)"
echo ""
echo "🔍 DNS Servers:"
grep nameserver /etc/resolv.conf | head -3
echo ""
echo "=========================================="
```

---

## CloudShell Quick Links

- 🇺🇸 us-east-1: https://us-east-1.console.aws.amazon.com/cloudshell
- 🇪🇺 eu-west-1: https://eu-west-1.console.aws.amazon.com/cloudshell
- 🇪🇺 eu-west-2: https://eu-west-2.console.aws.amazon.com/cloudshell
- 🇸🇬 ap-southeast-1: https://ap-southeast-1.console.aws.amazon.com/cloudshell

