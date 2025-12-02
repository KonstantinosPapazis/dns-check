#!/usr/bin/env python3
"""
Quick DNS Geolocation Check Script

Run from AWS CloudShell in each region:
    python3 quick_check.py myapp.kostas.com

Or invoke as a Lambda directly:
    aws lambda invoke --function-name test-check --payload '{"domain":"myapp.kostas.com"}' out.json
"""

import json
import socket
import ssl
import urllib.request
import urllib.error
import os
import sys
from datetime import datetime

# ANSI colors
GREEN = '\033[92m'
RED = '\033[91m'
YELLOW = '\033[93m'
BOLD = '\033[1m'
RESET = '\033[0m'


def get_current_region():
    """Try to determine current AWS region."""
    # From environment
    region = os.environ.get('AWS_REGION') or os.environ.get('AWS_DEFAULT_REGION')
    if region:
        return region
    
    # From EC2/CloudShell metadata
    try:
        req = urllib.request.Request(
            'http://169.254.169.254/latest/meta-data/placement/region',
            headers={'X-aws-ec2-metadata-token-ttl-seconds': '21600'}
        )
        with urllib.request.urlopen(req, timeout=2) as resp:
            return resp.read().decode()
    except:
        pass
    
    return 'unknown'


def resolve_dns(domain):
    """Resolve domain to IP addresses."""
    try:
        result = socket.gethostbyname_ex(domain)
        return {
            'success': True,
            'canonical': result[0],
            'aliases': result[1],
            'ips': result[2]
        }
    except socket.gaierror as e:
        return {'success': False, 'error': str(e)}


def check_url(url, timeout=10):
    """Make HTTP request and extract details."""
    ctx = ssl.create_default_context()
    
    try:
        req = urllib.request.Request(url, headers={
            'User-Agent': 'QuickCheck/1.0',
            'Accept': 'application/json'
        })
        
        start = datetime.now()
        with urllib.request.urlopen(req, timeout=timeout, context=ctx) as resp:
            elapsed = (datetime.now() - start).total_seconds()
            body = resp.read().decode()
            headers = dict(resp.headers)
            
            # Try to extract region from various sources
            served_region = None
            
            # Check headers
            for h in ['X-Served-By-Region', 'X-Region', 'X-Server-Region']:
                if h in headers:
                    served_region = headers[h]
                    break
            
            # Check JSON body
            if not served_region:
                try:
                    data = json.loads(body)
                    served_region = (
                        data.get('region') or 
                        data.get('aws_region') or 
                        data.get('server_region')
                    )
                except:
                    pass
            
            return {
                'success': True,
                'status': resp.status,
                'elapsed': elapsed,
                'headers': headers,
                'body': body[:1000],
                'served_region': served_region
            }
            
    except urllib.error.HTTPError as e:
        return {
            'success': False,
            'status': e.code,
            'error': str(e),
            'headers': dict(e.headers) if e.headers else {}
        }
    except Exception as e:
        return {'success': False, 'error': str(e)}


def main():
    domain = sys.argv[1] if len(sys.argv) > 1 else 'myapp.kostas.com'
    endpoint = sys.argv[2] if len(sys.argv) > 2 else '/health'
    url = f'https://{domain}{endpoint}'
    
    print("=" * 50)
    print(f"{BOLD}🌍 DNS Geolocation Quick Check{RESET}")
    print("=" * 50)
    print()
    
    # Current region
    current_region = get_current_region()
    print(f"📍 Running from region: {BOLD}{current_region}{RESET}")
    print(f"🔗 Target URL: {url}")
    print()
    
    # DNS check
    print(f"{BOLD}1️⃣  DNS Resolution{RESET}")
    dns = resolve_dns(domain)
    if dns['success']:
        print(f"   Resolved IPs: {', '.join(dns['ips'])}")
    else:
        print(f"   {RED}Failed: {dns['error']}{RESET}")
    print()
    
    # HTTP check
    print(f"{BOLD}2️⃣  HTTP Request{RESET}")
    result = check_url(url)
    
    if result['success']:
        print(f"   Status: {result['status']}")
        print(f"   Response time: {result['elapsed']:.3f}s")
        
        # Show relevant headers
        print()
        print(f"{BOLD}3️⃣  Response Headers{RESET}")
        for h, v in result['headers'].items():
            if any(x in h.lower() for x in ['region', 'server', 'x-amz', 'via', 'cache']):
                print(f"   {h}: {v}")
        
        # Show body preview
        print()
        print(f"{BOLD}4️⃣  Response Body{RESET}")
        try:
            pretty = json.dumps(json.loads(result['body']), indent=2)
            for line in pretty.split('\n')[:15]:
                print(f"   {line}")
        except:
            print(f"   {result['body'][:300]}")
        
        # Final verdict
        print()
        print("=" * 50)
        served = result.get('served_region')
        if served:
            if served.lower().replace('-', '') == current_region.lower().replace('-', ''):
                print(f"{GREEN}✅ MATCH{RESET}: {current_region} → served by {served}")
            else:
                print(f"{RED}❌ MISMATCH{RESET}: {current_region} → served by {served}")
        else:
            print(f"{YELLOW}⚠️  Could not detect serving region{RESET}")
            print("   Add X-Served-By-Region header or 'region' in JSON body")
        print("=" * 50)
    else:
        print(f"   {RED}Failed: {result.get('error', 'Unknown error')}{RESET}")


if __name__ == '__main__':
    main()

