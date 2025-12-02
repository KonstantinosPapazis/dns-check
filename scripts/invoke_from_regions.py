#!/usr/bin/env python3
"""
Quick Multi-Region DNS Check via Lambda

Creates temporary Lambda functions in each region, invokes them to test
geolocation routing, then cleans up. No permanent infrastructure needed.

Usage:
    python3 invoke_from_regions.py myapp.kostas.com

Requirements:
    - AWS credentials with Lambda permissions
    - pip install boto3
"""

import boto3
import json
import sys
import time
import zipfile
import io
import base64

REGIONS = ['us-east-1', 'eu-west-1', 'ap-southeast-1']

LAMBDA_CODE = '''
import json
import urllib.request
import ssl
import os

def lambda_handler(event, context):
    domain = event.get('domain', 'example.com')
    endpoint = event.get('endpoint', '/health')
    url = f'https://{domain}{endpoint}'
    region = os.environ.get('AWS_REGION', 'unknown')
    
    ctx = ssl.create_default_context()
    try:
        req = urllib.request.Request(url, headers={'User-Agent': f'RegionCheck/{region}'})
        with urllib.request.urlopen(req, timeout=10, context=ctx) as resp:
            body = resp.read().decode()
            headers = dict(resp.headers)
            
            served_region = headers.get('X-Served-By-Region')
            if not served_region:
                try:
                    data = json.loads(body)
                    served_region = data.get('region') or data.get('aws_region')
                except:
                    pass
            
            return {
                'probe_region': region,
                'served_region': served_region,
                'match': region == served_region if served_region else None,
                'status': resp.status,
                'body_preview': body[:200]
            }
    except Exception as e:
        return {
            'probe_region': region,
            'error': str(e)
        }
'''


def create_zip():
    """Create in-memory zip file with Lambda code."""
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, 'w', zipfile.ZIP_DEFLATED) as zf:
        zf.writestr('lambda_function.py', LAMBDA_CODE)
    return buffer.getvalue()


def main():
    domain = sys.argv[1] if len(sys.argv) > 1 else 'myapp.kostas.com'
    endpoint = sys.argv[2] if len(sys.argv) > 2 else '/health'
    
    print("=" * 60)
    print("🌍 Multi-Region DNS Geolocation Check")
    print(f"   Domain: {domain}")
    print(f"   Endpoint: {endpoint}")
    print("=" * 60)
    print()
    
    zip_bytes = create_zip()
    results = []
    
    for region in REGIONS:
        print(f"🔄 Testing from {region}...")
        
        try:
            # Create Lambda client for region
            lambda_client = boto3.client('lambda', region_name=region)
            iam_client = boto3.client('iam')
            
            # Check if we can use existing role or need basic execution
            function_name = f'dns-check-temp-{int(time.time())}'
            
            # Get account ID for role ARN
            sts = boto3.client('sts')
            account_id = sts.get_caller_identity()['Account']
            
            # Try to use basic execution role (might already exist)
            role_arn = f'arn:aws:iam::{account_id}:role/dns-check-temp-role'
            
            # Create role if doesn't exist
            try:
                iam_client.get_role(RoleName='dns-check-temp-role')
            except iam_client.exceptions.NoSuchEntityException:
                print(f"   Creating temporary IAM role...")
                iam_client.create_role(
                    RoleName='dns-check-temp-role',
                    AssumeRolePolicyDocument=json.dumps({
                        'Version': '2012-10-17',
                        'Statement': [{
                            'Effect': 'Allow',
                            'Principal': {'Service': 'lambda.amazonaws.com'},
                            'Action': 'sts:AssumeRole'
                        }]
                    })
                )
                iam_client.attach_role_policy(
                    RoleName='dns-check-temp-role',
                    PolicyArn='arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole'
                )
                time.sleep(10)  # Wait for role to propagate
            
            # Create Lambda function
            print(f"   Creating temporary Lambda in {region}...")
            lambda_client.create_function(
                FunctionName=function_name,
                Runtime='python3.11',
                Role=role_arn,
                Handler='lambda_function.lambda_handler',
                Code={'ZipFile': zip_bytes},
                Timeout=30
            )
            
            # Wait for function to be ready
            time.sleep(3)
            
            # Invoke
            print(f"   Invoking Lambda...")
            response = lambda_client.invoke(
                FunctionName=function_name,
                Payload=json.dumps({'domain': domain, 'endpoint': endpoint})
            )
            
            result = json.loads(response['Payload'].read().decode())
            results.append(result)
            
            # Print result
            if 'error' in result:
                print(f"   ❌ Error: {result['error']}")
            elif result.get('match') is True:
                print(f"   ✅ MATCH: {result['probe_region']} → {result['served_region']}")
            elif result.get('match') is False:
                print(f"   ❌ MISMATCH: {result['probe_region']} → {result['served_region']}")
            else:
                print(f"   ⚠️  Region unknown: {result.get('body_preview', '')[:50]}")
            
            # Cleanup
            print(f"   Cleaning up...")
            lambda_client.delete_function(FunctionName=function_name)
            
        except Exception as e:
            print(f"   ❌ Failed: {e}")
            results.append({'probe_region': region, 'error': str(e)})
        
        print()
    
    # Summary
    print("=" * 60)
    print("📊 SUMMARY")
    print("=" * 60)
    
    matches = sum(1 for r in results if r.get('match') is True)
    mismatches = sum(1 for r in results if r.get('match') is False)
    errors = sum(1 for r in results if 'error' in r)
    
    print(f"   ✅ Matches: {matches}")
    print(f"   ❌ Mismatches: {mismatches}")
    print(f"   ⚠️  Errors/Unknown: {errors + (len(results) - matches - mismatches - errors)}")
    print()
    
    if mismatches > 0:
        print("🚨 GEOLOCATION ROUTING ISSUE DETECTED!")
        sys.exit(1)
    elif matches == len(REGIONS):
        print("✅ All regions routing correctly!")
    else:
        print("⚠️  Could not verify all regions - check app returns region info")


if __name__ == '__main__':
    main()

