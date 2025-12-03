# Command-Line Tools Guide for Region Verification

Quick reference for using `curl`, `nslookup`, `dig`, and other command-line tools to verify which AWS region is serving your application.

## Quick Start

Run the automated script:
```bash
./scripts/check_region.sh myapp.kostas.com
```

Or use individual commands below.

## Essential Commands

### 1. Resolve Domain to IP

```bash
# Using dig (recommended)
dig +short myapp.kostas.com

# Using nslookup
nslookup myapp.kostas.com

# Get all A records
dig myapp.kostas.com A +noall +answer
```

### 2. Check IP Geolocation

```bash
# Replace with your actual IP
IP="52.84.123.45"

# Option 1: ipapi.co (free, no API key needed)
curl -s "https://ipapi.co/$IP/json/" | jq '{city, region, country_code, org}'

# Option 2: ip-api.com (free, no API key needed)
curl -s "http://ip-api.com/json/$IP" | jq '{city, regionName, country, isp}'

# Option 3: Check AWS IP ranges directly
curl -s "https://ip-ranges.amazonaws.com/ip-ranges.json" | \
  jq --arg ip "$IP" '.prefixes[] | select(.ip_prefix | as $p | $ip | test("^" + ($p | split("/")[0] | split(".")[0:2] | join("\\.")))) | {region, service}'
```

### 3. Check HTTP Headers

```bash
# Get all headers
curl -I https://myapp.kostas.com/health

# Look for region headers specifically
curl -I https://myapp.kostas.com/health 2>&1 | grep -iE "region|location|edge|x-"

# Verbose output (shows all request/response details)
curl -v https://myapp.kostas.com/health 2>&1 | grep -E "^< |^> "
```

### 4. Measure Response Time

```bash
# Single measurement
curl -o /dev/null -s -w "Time: %{time_total}s\n" https://myapp.kostas.com/health

# Multiple measurements with average
for i in {1..10}; do
    curl -o /dev/null -s -w "%{time_total}\n" https://myapp.kostas.com/health
done | awk '{sum+=$1; count++} END {print "Average: " sum/count "s"}'
```

### 5. Check Network Path

```bash
# Traceroute (shows network hops)
traceroute myapp.kostas.com

# On macOS, you might need:
sudo traceroute myapp.kostas.com

# Or use mtr (more detailed, install: brew install mtr)
mtr --report --report-cycles 10 myapp.kostas.com
```

## One-Liner Commands

### Complete Check (All-in-One)

```bash
DOMAIN="myapp.kostas.com" && \
IP=$(dig +short $DOMAIN | head -1) && \
echo "=== Region Check for $DOMAIN ===" && \
echo "IP: $IP" && \
echo "" && \
echo "Geolocation:" && \
curl -s "https://ipapi.co/$IP/json/" | jq '{city, region, country_code, org}' && \
echo "" && \
echo "AWS Region:" && \
curl -s "https://ip-ranges.amazonaws.com/ip-ranges.json" | \
  jq -r --arg ip "$IP" '.prefixes[] | select(.ip_prefix | as $p | $ip | test("^" + ($p | split("/")[0] | split(".")[0:2] | join("\\.")))) | "\(.region) - \(.service)"' | head -3 && \
echo "" && \
echo "Latency:" && \
curl -o /dev/null -s -w "%{time_total}s\n" "https://$DOMAIN/health"
```

### Quick IP to Region Check

```bash
# Function to add to ~/.bashrc or ~/.zshrc
check_aws_region() {
    local IP=$1
    echo "Checking IP: $IP"
    echo "Geolocation:"
    curl -s "https://ipapi.co/$IP/json/" | jq '{city, region, country_code, org}'
    echo ""
    echo "AWS Region:"
    curl -s "https://ip-ranges.amazonaws.com/ip-ranges.json" | \
      jq -r --arg ip "$IP" '.prefixes[] | select(.ip_prefix | as $p | $ip | test("^" + ($p | split("/")[0] | split(".")[0:2] | join("\\.")))) | "\(.region) - \(.service)"' | head -5
}

# Usage
check_aws_region "52.84.123.45"
```

## Testing from Different Locations

### Compare Latencies

If you have access to different geographic locations (VPN, different servers, etc.):

```bash
# Test from current location
echo "Current location:"
curl -o /dev/null -s -w "%{time_total}s\n" https://myapp.kostas.com/health

# If you have VPN access to US East
# Connect to US East VPN, then:
echo "US East:"
curl -o /dev/null -s -w "%{time_total}s\n" https://myapp.kostas.com/health

# If you have VPN access to EU
# Connect to EU VPN, then:
echo "EU:"
curl -o /dev/null -s -w "%{time_total}s\n" https://myapp.kostas.com/health
```

**Expected:** Lowest latency indicates the region serving your request.

## Interpreting Results

### DNS Resolution

- **Single IP**: Direct resolution
- **Multiple IPs**: Load balancing (check all IPs)
- **CNAME**: Points to another domain (follow the chain)

### IP Geolocation

- **AWS Organization**: Look for "Amazon", "AWS", "Amazon Technologies"
- **Region Code**: May show AWS region (e.g., "us-east-1")
- **City/Country**: Geographic location of IP

### AWS IP Ranges

- **Region Match**: If IP matches AWS region ranges, high confidence (80-90%)
- **Service**: Should be "EC2" or "AMAZON"
- **No Match**: May be behind CDN or load balancer

### Latency

- **< 50ms**: Same region or very close
- **50-150ms**: Same continent, different region
- **> 150ms**: Different continent

### HTTP Headers

Look for these headers:
- `X-Served-From-Region`: Explicit region (100% accurate)
- `X-Amzn-Region`: AWS region
- `X-Region`: Generic region header
- `X-Edge-Location`: CloudFront edge location
- `Server`: May contain region info

## Common Use Cases

### Use Case 1: Quick Check

```bash
# Just want to know the IP and region
DOMAIN="myapp.kostas.com"
IP=$(dig +short $DOMAIN | head -1)
echo "IP: $IP"
curl -s "https://ipapi.co/$IP/json/" | jq '{region, city, org}'
```

### Use Case 2: Verify F5 Routing

```bash
# Test from your location
DOMAIN="myapp.kostas.com"
echo "Testing from current location:"
curl -o /dev/null -s -w "Latency: %{time_total}s\n" "https://$DOMAIN/health"

# Check which region IP belongs to
IP=$(dig +short $DOMAIN | head -1)
curl -s "https://ip-ranges.amazonaws.com/ip-ranges.json" | \
  jq -r --arg ip "$IP" '.prefixes[] | select(.ip_prefix | as $p | $ip | test("^" + ($p | split("/")[0] | split(".")[0:2] | join("\\.")))) | .region' | head -1
```

### Use Case 3: Compare Multiple Regions

```bash
# If you have access to test from different regions
DOMAIN="myapp.kostas.com"

echo "=== Latency Comparison ==="
echo "From US East:"
# (Connect to US East VPN/server first)
curl -o /dev/null -s -w "%{time_total}s\n" "https://$DOMAIN/health"

echo "From EU:"
# (Connect to EU VPN/server first)
curl -o /dev/null -s -w "%{time_total}s\n" "https://$DOMAIN/health"

echo "From Asia:"
# (Connect to Asia VPN/server first)
curl -o /dev/null -s -w "%{time_total}s\n" "https://$DOMAIN/health"
```

## Troubleshooting

### Issue: Can't resolve domain

```bash
# Check DNS servers
dig myapp.kostas.com @8.8.8.8  # Google DNS
dig myapp.kostas.com @1.1.1.1  # Cloudflare DNS

# Check if domain exists
whois myapp.kostas.com
```

### Issue: IP geolocation shows wrong location

- IP geolocation is not 100% accurate (70-90% typically)
- CDN IPs may not match origin region
- Load balancer IPs may be in different location
- Use multiple methods (IP + latency + headers) for better accuracy

### Issue: No region headers

- Normal if load balancer doesn't add headers
- Rely on IP geolocation and latency instead
- Consider configuring F5 to add region headers

### Issue: High latency

- Check your network connection
- Verify you're testing the correct endpoint
- Compare with baseline measurements
- Test from different locations

## Advanced: Using AWS CLI

If you have AWS CLI configured:

```bash
# Check if IP belongs to your AWS account's VPC
aws ec2 describe-network-interfaces --filters "Name=addresses.private-ip-address,Values=10.0.1.5"

# Get your VPC CIDR blocks
aws ec2 describe-vpcs --query 'Vpcs[*].[VpcId,CidrBlock]' --output table
```

## Next Steps

1. **Run the automated script**: `./scripts/check_region.sh myapp.kostas.com`
2. **Test from different locations** (if possible)
3. **Compare results** with expected regions
4. **Set up automated monitoring** (Lambda solution) for continuous verification

## See Also

- `MANUAL_VERIFICATION.md` - Detailed manual verification guide
- `scripts/check_region.sh` - Automated verification script
- `README_NO_APP_CHANGES.md` - Automated solution without app changes

