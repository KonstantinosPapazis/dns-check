# Quick Reference - DNS/IP Check Commands

Run these from **AWS CloudShell** in each region to test geolocation routing.

## Get Server IP

```bash
# What IP did I connect to?
curl -s -o /dev/null -w "%{remote_ip}\n" https://myapp.kostas.com
```

## DNS Lookup

```bash
# dig (cleanest)
dig +short myapp.kostas.com

# nslookup
nslookup myapp.kostas.com | grep -A1 "Name:" | grep Address

# host
host myapp.kostas.com | awk '/has address/ {print $4}'
```

## IP + Geolocation (where is that server?)

```bash
curl -s -o /dev/null -w "%{remote_ip}" https://myapp.kostas.com | xargs -I{} curl -s ip-api.com/{}
```

## IP + Response Time

```bash
curl -s -w "IP: %{remote_ip}\nTime: %{time_total}s\n" -o /dev/null https://myapp.kostas.com
```

## Check Response Headers

```bash
curl -sI https://myapp.kostas.com | grep -iE "^(server|x-|via):"
```

## All-in-One Diagnostic

```bash
IP=$(curl -s -o /dev/null -w "%{remote_ip}" https://myapp.kostas.com) && \
echo "Region: $AWS_REGION" && \
echo "Server IP: $IP" && \
curl -s "ip-api.com/$IP?fields=country,city,org" | tr ',' '\n'
```

---

## CloudShell Quick Links

- 🇺🇸 [us-east-1](https://us-east-1.console.aws.amazon.com/cloudshell)
- 🇪🇺 [eu-west-1](https://eu-west-1.console.aws.amazon.com/cloudshell)
- 🇸🇬 [ap-southeast-1](https://ap-southeast-1.console.aws.amazon.com/cloudshell)

---

## Expected Results

If F5 geolocation is working correctly:

| CloudShell Region | Should Connect To |
|-------------------|-------------------|
| us-east-1 | US-based IP |
| eu-west-1 | EU-based IP |
| ap-southeast-1 | Asia-based IP |

If all regions return the **same IP**, geolocation routing may not be working.

