"""
Regional DNS/Geolocation Validation Lambda

This Lambda function validates that requests from this AWS region
are being correctly routed to the expected ECS cluster by the F5 load balancer.

The function:
1. Resolves the DNS for the target domain
2. Makes an HTTP request to the application
3. Validates the response indicates the correct regional backend
4. Publishes metrics to CloudWatch
"""

import json
import os
import socket
import urllib.request
import urllib.error
import ssl
import boto3
from datetime import datetime

# Configuration from environment variables
DOMAIN = os.environ.get('TARGET_DOMAIN', 'myapp.kostas.com')
EXPECTED_REGION = os.environ.get('EXPECTED_REGION', os.environ.get('AWS_REGION', 'unknown'))
HEALTH_ENDPOINT = os.environ.get('HEALTH_ENDPOINT', '/health')
REGION_HEADER = os.environ.get('REGION_HEADER', 'X-Served-By-Region')
TIMEOUT_SECONDS = int(os.environ.get('TIMEOUT_SECONDS', '10'))

# CloudWatch client
cloudwatch = boto3.client('cloudwatch')


def resolve_dns(domain: str) -> dict:
    """Resolve DNS and return IP addresses."""
    try:
        # Get all IP addresses for the domain
        ips = socket.gethostbyname_ex(domain)
        return {
            'success': True,
            'hostname': ips[0],
            'aliases': ips[1],
            'ip_addresses': ips[2]
        }
    except socket.gaierror as e:
        return {
            'success': False,
            'error': str(e)
        }


def check_endpoint(domain: str, endpoint: str) -> dict:
    """Make HTTP request and extract region information."""
    url = f"https://{domain}{endpoint}"
    
    # Create SSL context (you may need to adjust for self-signed certs)
    ctx = ssl.create_default_context()
    
    try:
        request = urllib.request.Request(
            url,
            headers={
                'User-Agent': f'DNS-Check-Lambda/{EXPECTED_REGION}',
                'X-Probe-Region': EXPECTED_REGION
            }
        )
        
        with urllib.request.urlopen(request, timeout=TIMEOUT_SECONDS, context=ctx) as response:
            body = response.read().decode('utf-8')
            headers = dict(response.headers)
            status_code = response.status
            
            # Try to extract region from response
            served_region = None
            
            # Method 1: Check for region header
            if REGION_HEADER in headers:
                served_region = headers[REGION_HEADER]
            
            # Method 2: Try to parse JSON body for region info
            if not served_region:
                try:
                    json_body = json.loads(body)
                    served_region = (
                        json_body.get('region') or 
                        json_body.get('aws_region') or
                        json_body.get('served_by_region') or
                        json_body.get('server_region')
                    )
                except json.JSONDecodeError:
                    pass
            
            return {
                'success': True,
                'status_code': status_code,
                'served_region': served_region,
                'headers': headers,
                'body_preview': body[:500] if len(body) > 500 else body,
                'response_time_indication': 'measured_separately'
            }
            
    except urllib.error.HTTPError as e:
        return {
            'success': False,
            'status_code': e.code,
            'error': str(e),
            'headers': dict(e.headers) if e.headers else {}
        }
    except urllib.error.URLError as e:
        return {
            'success': False,
            'error': str(e.reason)
        }
    except Exception as e:
        return {
            'success': False,
            'error': str(e)
        }


def publish_metrics(check_result: dict):
    """Publish check results to CloudWatch."""
    dimensions = [
        {'Name': 'Domain', 'Value': DOMAIN},
        {'Name': 'ProbeRegion', 'Value': EXPECTED_REGION}
    ]
    
    metrics = []
    
    # DNS Resolution Success
    metrics.append({
        'MetricName': 'DNSResolutionSuccess',
        'Dimensions': dimensions,
        'Value': 1 if check_result['dns']['success'] else 0,
        'Unit': 'Count'
    })
    
    # HTTP Check Success
    http_success = check_result['http'].get('success', False)
    metrics.append({
        'MetricName': 'HTTPCheckSuccess',
        'Dimensions': dimensions,
        'Value': 1 if http_success else 0,
        'Unit': 'Count'
    })
    
    # Region Match (the key metric!)
    region_match = check_result.get('region_match', False)
    metrics.append({
        'MetricName': 'RegionMatchSuccess',
        'Dimensions': dimensions,
        'Value': 1 if region_match else 0,
        'Unit': 'Count'
    })
    
    # Geolocation Routing Failure (inverse of region match for easier alarming)
    metrics.append({
        'MetricName': 'GeolocationRoutingFailure',
        'Dimensions': dimensions,
        'Value': 0 if region_match else 1,
        'Unit': 'Count'
    })
    
    try:
        cloudwatch.put_metric_data(
            Namespace='DNS-Check/Geolocation',
            MetricData=metrics
        )
    except Exception as e:
        print(f"Failed to publish metrics: {e}")


def lambda_handler(event, context):
    """
    Main Lambda handler.
    
    Expected behavior:
    - Resolve DNS for the target domain
    - Make HTTP request to health endpoint
    - Validate response indicates correct regional routing
    - Publish metrics and return results
    """
    print(f"Starting DNS check from region: {EXPECTED_REGION}")
    print(f"Target domain: {DOMAIN}")
    print(f"Health endpoint: {HEALTH_ENDPOINT}")
    
    result = {
        'timestamp': datetime.utcnow().isoformat(),
        'probe_region': EXPECTED_REGION,
        'expected_region': EXPECTED_REGION,
        'domain': DOMAIN,
        'dns': {},
        'http': {},
        'region_match': False,
        'overall_success': False
    }
    
    # Step 1: DNS Resolution
    print("Step 1: Resolving DNS...")
    result['dns'] = resolve_dns(DOMAIN)
    print(f"DNS Result: {json.dumps(result['dns'])}")
    
    if not result['dns']['success']:
        result['failure_reason'] = 'DNS resolution failed'
        publish_metrics(result)
        return result
    
    # Step 2: HTTP Check
    print("Step 2: Making HTTP request...")
    result['http'] = check_endpoint(DOMAIN, HEALTH_ENDPOINT)
    print(f"HTTP Result: {json.dumps(result['http'], default=str)}")
    
    if not result['http']['success']:
        result['failure_reason'] = f"HTTP request failed: {result['http'].get('error', 'unknown')}"
        publish_metrics(result)
        return result
    
    # Step 3: Validate Region
    print("Step 3: Validating region...")
    served_region = result['http'].get('served_region')
    
    if served_region:
        # Normalize region names for comparison (handle variations)
        expected_normalized = EXPECTED_REGION.lower().replace('-', '').replace('_', '')
        served_normalized = served_region.lower().replace('-', '').replace('_', '')
        
        result['served_region'] = served_region
        result['region_match'] = expected_normalized == served_normalized
        
        if result['region_match']:
            result['overall_success'] = True
            print(f"✓ Region match! Expected: {EXPECTED_REGION}, Got: {served_region}")
        else:
            result['failure_reason'] = f"Region mismatch! Expected: {EXPECTED_REGION}, Got: {served_region}"
            print(f"✗ {result['failure_reason']}")
    else:
        result['failure_reason'] = "Could not determine served region from response"
        result['region_detection_failed'] = True
        print(f"⚠ {result['failure_reason']}")
        # If we can't detect region but HTTP succeeded, it's a partial success
        # You may want to adjust this logic based on your requirements
    
    # Step 4: Publish Metrics
    print("Step 4: Publishing metrics to CloudWatch...")
    publish_metrics(result)
    
    print(f"Final result: {json.dumps(result, default=str)}")
    return result


# For local testing
if __name__ == '__main__':
    # Mock event and context for local testing
    test_event = {}
    test_context = type('Context', (), {'function_name': 'test'})()
    
    result = lambda_handler(test_event, test_context)
    print(json.dumps(result, indent=2, default=str))

