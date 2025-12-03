# Manual Region Verification Using Command-Line Tools

This guide shows you how to verify which AWS region is serving your application using simple command-line tools like `curl`, `nslookup`, `dig`, and others.

## Quick Commands

### Method 1: DNS Resolution + IP Geolocation

```bash
# Step 1: Resolve domain to IP addresses
nslookup myapp.kostas.com
# or
dig +short myapp.kostas.com

# Step 2: Check IP geolocation
curl -s "https://ipapi.co/52.84.123.45/json/" | jq '.region, .country_code'
# or
curl -s "http://ip-api.com/json/52.84.123.45" | jq '.region, .country'

# Step 3: Check if IP belongs to AWS and which region
curl -s "https://ip-ranges.amazonaws.com/ip-ranges.json" | \
  jq --arg ip "52.84.123.45" '.prefixes[] | select(.ip_prefix | test("^52\\.84\\.")) | .region'
```

### Method 2: HTTP Headers Analysis

```bash
# Check all response headers
curl -I https://myapp.kostas.com/health

# Look for region-indicating headers
curl -I https://myapp.kostas.com/health | grep -i "region\|location\|edge"

# Get detailed header information
curl -v https://myapp.kostas.com/health 2>&1 | grep -i "< "
```

### Method 3: Response Time Measurement

```bash
# Measure response time (lower = closer region)
time curl -s -o /dev/null -w "%{time_total}" https://myapp.kostas.com/health

# Multiple measurements
for i in {1..5}; do
  echo -n "Attempt $i: "
  curl -s -o /dev/null -w "%{time_total}s\n" https://myapp.kostas.com/health
done
```

### Method 4: Traceroute (Network Path)

```bash
# See network path to your application
traceroute myapp.kostas.com

# On macOS (uses mtr or similar)
# Install: brew install mtr
mtr --report --report-cycles 10 myapp.kostas.com
```

## Complete Verification Script

Save this as `check_region.sh`:

```bash
#!/bin/bash

DOMAIN="${1:-myapp.kostas.com}"
PROTOCOL="${2:-https}"

echo "=========================================="
echo "Region Verification for: $DOMAIN"
echo "=========================================="
echo ""

# 1. DNS Resolution
echo "1. DNS Resolution"
echo "------------------"
IPS=$(dig +short $DOMAIN | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$')
if [ -z "$IPS" ]; then
    IPS=$(nslookup $DOMAIN | grep -A 1 "Name:" | tail -1 | awk '{print $2}')
fi

echo "Resolved IPs:"
echo "$IPS"
echo ""

# 2. IP Geolocation
echo "2. IP Geolocation"
echo "-----------------"
for IP in $IPS; do
    echo "Checking IP: $IP"
    
    # Using ipapi.co
    REGION=$(curl -s "https://ipapi.co/$IP/json/" | jq -r '.region // .region_code // "unknown"')
    COUNTRY=$(curl -s "https://ipapi.co/$IP/json/" | jq -r '.country_code // "unknown"')
    CITY=$(curl -s "https://ipapi.co/$IP/json/" | jq -r '.city // "unknown"')
    
    echo "  Location: $CITY, $REGION, $COUNTRY"
    
    # Check AWS IP ranges
    echo "  Checking AWS IP ranges..."
    AWS_REGION=$(curl -s "https://ip-ranges.amazonaws.com/ip-ranges.json" | \
      jq -r --arg ip "$IP" '.prefixes[] | select(.ip_prefix | as $prefix | $ip | test("^" + ($prefix | split("/")[0] | split(".")[0:3] | join("\\.")))) | .region' | head -1)
    
    if [ -n "$AWS_REGION" ] && [ "$AWS_REGION" != "null" ]; then
        echo "  ✓ AWS Region: $AWS_REGION"
    else
        echo "  ? Not found in AWS IP ranges (may be behind CDN/LB)"
    fi
    echo ""
done

# 3. HTTP Headers
echo "3. HTTP Response Headers"
echo "------------------------"
HEADERS=$(curl -s -I "$PROTOCOL://$DOMAIN/health" 2>&1)
echo "$HEADERS" | grep -i "region\|location\|edge\|server\|x-" || echo "No region headers found"
echo ""

# 4. Response Time
echo "4. Response Time Measurement"
echo "----------------------------"
echo "Measuring latency (lower = closer region):"
TIMES=()
for i in {1..5}; do
    TIME=$(curl -s -o /dev/null -w "%{time_total}" "$PROTOCOL://$DOMAIN/health")
    TIMES+=($TIME)
    printf "  Attempt %d: %.3fs\n" $i $TIME
done

AVG=$(echo "${TIMES[@]}" | awk '{sum=0; for(i=1;i<=NF;i++) sum+=$i; print sum/NF}')
MIN=$(echo "${TIMES[@]}" | tr ' ' '\n' | sort -n | head -1)
MAX=$(echo "${TIMES[@]}" | tr ' ' '\n' | sort -n | tail -1)

echo ""
echo "  Average: ${AVG}s"
echo "  Min: ${MIN}s"
echo "  Max: ${MAX}s"
echo ""

# 5. Summary
echo "=========================================="
echo "Summary"
echo "=========================================="
echo "Domain: $DOMAIN"
echo "IP Addresses: $IPS"
echo "Average Latency: ${AVG}s"
echo ""
echo "Expected Latency Ranges:"
echo "  us-east-1: 10-100ms (if you're in US East)"
echo "  eu-west-1: 10-100ms (if you're in EU)"
echo "  ap-southeast-1: 10-100ms (if you're in Asia)"
echo ""
echo "Lower latency typically indicates closer region."
```

Make it executable:
```bash
chmod +x check_region.sh
./check_region.sh myapp.kostas.com
```

## Step-by-Step Manual Verification

### Step 1: Resolve Domain to IP

```bash
# Using nslookup
nslookup myapp.kostas.com

# Using dig (more detailed)
dig myapp.kostas.com +short

# Get all A records
dig myapp.kostas.com A +noall +answer
```

**What to look for:**
- IP addresses that belong to AWS ranges
- Multiple IPs (may indicate load balancing)

### Step 2: Check IP Geolocation

#### Option A: Using ipapi.co (Free)

```bash
IP="52.84.123.45"  # Replace with your IP
curl -s "https://ipapi.co/$IP/json/" | jq '.'
```

**Key fields:**
- `region`: AWS region code (if available)
- `city`: City location
- `country_code`: Country code
- `org`: Organization (should show "Amazon" or "AWS")

#### Option B: Using ip-api.com (Free)

```bash
IP="52.84.123.45"
curl -s "http://ip-api.com/json/$IP" | jq '.'
```

**Key fields:**
- `region`: Region name
- `country`: Country
- `isp`: ISP (should show "Amazon" or "AWS")

#### Option C: Using AWS IP Ranges

```bash
# Download AWS IP ranges
curl -s "https://ip-ranges.amazonaws.com/ip-ranges.json" > aws-ip-ranges.json

# Check if your IP matches a region
IP="52.84.123.45"
jq --arg ip "$IP" '.prefixes[] | select(.ip_prefix | as $prefix | $ip | test("^" + ($prefix | split("/")[0] | split(".")[0:3] | join("\\.")))) | {region: .region, service: .service, ip_prefix: .ip_prefix}' aws-ip-ranges.json
```

**What to look for:**
- `region`: Should match expected region (e.g., "us-east-1")
- `service`: Should be "EC2" or "AMAZON"

### Step 3: Check HTTP Headers

```bash
# Get all headers
curl -I https://myapp.kostas.com/health

# Look for region headers
curl -I https://myapp.kostas.com/health 2>&1 | grep -iE "region|location|edge|x-"

# Get full response with headers
curl -v https://myapp.kostas.com/health 2>&1 | grep -E "^< |^> "
```

**Headers to check:**
- `X-Served-From-Region`
- `X-Amzn-Region`
- `X-Region`
- `X-Edge-Location`
- `X-CloudFront-Region`
- `Server` (may contain region info)

### Step 4: Measure Latency

```bash
# Single measurement
curl -o /dev/null -s -w "Time: %{time_total}s\n" https://myapp.kostas.com/health

# Multiple measurements
for i in {1..10}; do
    echo -n "Test $i: "
    curl -o /dev/null -s -w "%{time_total}s\n" https://myapp.kostas.com/health
done | awk '{sum+=$1; count++} END {print "Average: " sum/count "s"}'
```

**What to expect:**
- **Same region**: 10-50ms
- **Different region (same continent)**: 50-150ms
- **Different continent**: 150-300ms+

### Step 5: Check Network Path

```bash
# Traceroute (shows network path)
traceroute myapp.kostas.com

# On macOS, you might need:
sudo traceroute myapp.kostas.com

# Or use mtr (more detailed)
mtr --report --report-cycles 10 myapp.kostas.com
```

**What to look for:**
- AWS internal routing (amazon.com, aws.com domains)
- Geographic location of hops
- Final hop should be in expected region

## AWS-Specific Commands

### Check if IP belongs to AWS

```bash
# Download AWS IP ranges
curl -s "https://ip-ranges.amazonaws.com/ip-ranges.json" > /tmp/aws-ranges.json

# Function to check IP
check_aws_region() {
    local IP=$1
    jq -r --arg ip "$IP" '
        .prefixes[] | 
        select(.ip_prefix | as $prefix | 
            ($ip | split(".") | map(tonumber)) as $ip_parts |
            ($prefix | split("/")[0] | split(".") | map(tonumber)) as $prefix_parts |
            ($prefix | split("/")[1] | tonumber) as $mask |
            (if $mask <= 8 then $ip_parts[0] == $prefix_parts[0]
             elif $mask <= 16 then ($ip_parts[0] == $prefix_parts[0] and $ip_parts[1] == $prefix_parts[1])
             elif $mask <= 24 then ($ip_parts[0] == $prefix_parts[0] and $ip_parts[1] == $prefix_parts[1] and $ip_parts[2] == $prefix_parts[2])
             else true end)
        ) | "\(.region) - \(.service) - \(.ip_prefix)"
    ' /tmp/aws-ranges.json
}

# Usage
check_aws_region "52.84.123.45"
```

### Get AWS Region from IP Prefix

```bash
# Simple check using IP prefix matching
IP="52.84.123.45"
PREFIX=$(echo $IP | cut -d. -f1-2)  # Get first two octets

curl -s "https://ip-ranges.amazonaws.com/ip-ranges.json" | \
  jq -r --arg prefix "$PREFIX" '.prefixes[] | select(.ip_prefix | startswith($prefix)) | "\(.region) - \(.service)"' | \
  head -5
```

## Testing from Different Locations

### Using VPN or Different Networks

If you have access to different geographic locations:

```bash
# Test from US East
curl -s -o /dev/null -w "US East: %{time_total}s\n" https://myapp.kostas.com/health

# Test from EU (if you have VPN/access)
# Connect to EU VPN, then:
curl -s -o /dev/null -w "EU: %{time_total}s\n" https://myapp.kostas.com/health

# Test from Asia (if you have VPN/access)
# Connect to Asia VPN, then:
curl -s -o /dev/null -w "Asia: %{time_total}s\n" https://myapp.kostas.com/health
```

**Expected results:**
- Lowest latency = region serving your request
- F5 should route to closest region

### Using Online Tools

Several online tools can test from different locations:

1. **Pingdom** (https://tools.pingdom.com/)
2. **GTmetrix** (https://gtmetrix.com/)
3. **WebPageTest** (https://www.webpagetest.org/)
4. **DNS Checker** (https://dnschecker.org/)

## Complete Example Workflow

```bash
#!/bin/bash
DOMAIN="myapp.kostas.com"

echo "=== Region Verification for $DOMAIN ==="
echo ""

# 1. DNS
echo "1. DNS Resolution:"
IP=$(dig +short $DOMAIN | head -1)
echo "   IP: $IP"
echo ""

# 2. Geolocation
echo "2. IP Geolocation:"
curl -s "https://ipapi.co/$IP/json/" | jq '{city, region, country_code, org}'
echo ""

# 3. AWS Region Check
echo "3. AWS Region Check:"
curl -s "https://ip-ranges.amazonaws.com/ip-ranges.json" | \
  jq -r --arg ip "$IP" '.prefixes[] | select(.ip_prefix | as $p | $ip | test("^" + ($p | split("/")[0] | split(".")[0:2] | join("\\.")))) | "   Region: \(.region), Service: \(.service)"' | \
  head -3
echo ""

# 4. HTTP Headers
echo "4. HTTP Headers:"
curl -s -I "https://$DOMAIN/health" | grep -iE "region|location|edge|x-" || echo "   No region headers found"
echo ""

# 5. Latency
echo "5. Latency Measurement:"
for i in {1..5}; do
    TIME=$(curl -s -o /dev/null -w "%{time_total}" "https://$DOMAIN/health")
    echo "   Test $i: ${TIME}s"
done
echo ""

echo "=== Analysis Complete ==="
```

## Interpreting Results

### DNS IP Geolocation

- **If IP matches AWS region IP ranges**: High confidence (80-90%)
- **If IP is from CDN (CloudFront, etc.)**: Lower confidence, check edge location
- **If IP is from load balancer**: May not show region directly

### Latency Measurements

- **< 50ms**: Likely same region or very close
- **50-150ms**: Same continent, different region
- **> 150ms**: Different continent

### HTTP Headers

- **If region header present**: 100% accurate
- **If no region headers**: Rely on IP geolocation and latency

## Limitations

⚠️ **DNS may resolve to multiple IPs** (load balancing)  
⚠️ **CDN IPs may not match origin region**  
⚠️ **Latency can vary** based on network conditions  
⚠️ **IP geolocation is not 100% accurate** (70-90% typically)

## Quick Reference

```bash
# One-liner to check region
DOMAIN="myapp.kostas.com" && \
IP=$(dig +short $DOMAIN | head -1) && \
echo "IP: $IP" && \
curl -s "https://ipapi.co/$IP/json/" | jq '{region, city, country_code}' && \
curl -s "https://ip-ranges.amazonaws.com/ip-ranges.json" | \
  jq -r --arg ip "$IP" '.prefixes[] | select(.ip_prefix | as $p | $ip | test("^" + ($p | split("/")[0] | split(".")[0:2] | join("\\.")))) | .region' | head -1
```

## Next Steps

1. Run these commands from your local machine
2. Compare results from different locations (if possible)
3. Use the results to verify F5 geolocation routing
4. Consider deploying automated monitoring (Lambda solution) for continuous verification

