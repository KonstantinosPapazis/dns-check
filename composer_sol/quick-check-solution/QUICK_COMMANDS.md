# Quick Command Reference

## 🚀 Fastest Way

```bash
# Run automated script
./scripts/check_region.sh myapp.kostas.com

# Or simple version (fewer dependencies)
./scripts/check_region_simple.sh myapp.kostas.com
```

## 📋 Individual Commands

### Get IP Address
```bash
dig +short myapp.kostas.com
# or
nslookup myapp.kostas.com
```

### Check IP Location
```bash
IP="52.84.123.45"  # Replace with your IP
curl -s "https://ipapi.co/$IP/json/" | jq '{city, region, country_code, org}'
```

### Check AWS Region
```bash
IP="52.84.123.45"
curl -s "https://ip-ranges.amazonaws.com/ip-ranges.json" | \
  jq -r --arg ip "$IP" '.prefixes[] | select(.ip_prefix | as $p | $ip | test("^" + ($p | split("/")[0] | split(".")[0:2] | join("\\.")))) | .region' | head -1
```

### Check HTTP Headers
```bash
curl -I https://myapp.kostas.com/health | grep -i region
```

### Measure Latency
```bash
curl -o /dev/null -s -w "%{time_total}s\n" https://myapp.kostas.com/health
```

## 🔥 One-Liner (Complete Check)

```bash
DOMAIN="myapp.kostas.com" && \
IP=$(dig +short $DOMAIN | head -1) && \
echo "IP: $IP" && \
curl -s "https://ipapi.co/$IP/json/" | jq '{region, city, org}' && \
curl -o /dev/null -s -w "Latency: %{time_total}s\n" "https://$DOMAIN/health"
```

## 📊 What to Look For

| Method | What It Tells You | Accuracy |
|--------|------------------|----------|
| **DNS IP** | Which IP serves the domain | Medium |
| **IP Geolocation** | Geographic location of IP | 70-90% |
| **AWS IP Ranges** | AWS region of IP | 80-90% |
| **HTTP Headers** | Region from load balancer | 100% (if present) |
| **Latency** | Proximity to region | 60-75% |

## 🎯 Expected Results

### Same Region
- Latency: **10-50ms**
- IP: Matches AWS region ranges
- Headers: May show region

### Different Region (Same Continent)
- Latency: **50-150ms**
- IP: Different AWS region
- Headers: May show different region

### Different Continent
- Latency: **150-300ms+**
- IP: Different continent
- Headers: May show different region

## 💡 Pro Tips

1. **Test multiple times** - Latency can vary
2. **Check from different locations** - VPN helps verify geolocation routing
3. **Combine methods** - Use IP + latency + headers for best accuracy
4. **Look for AWS org** - IP geolocation should show "Amazon" or "AWS"

## 📚 More Details

- `COMMAND_LINE_GUIDE.md` - Complete command reference
- `MANUAL_VERIFICATION.md` - Detailed verification guide
- `scripts/check_region.sh` - Full automated script

