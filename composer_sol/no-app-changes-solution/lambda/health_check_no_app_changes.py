"""
Lambda function to verify ECS service is being served from the correct region
WITHOUT requiring application code changes.

This function uses multiple methods to verify region:
1. IP Geolocation - Checks if response IP is from expected AWS region
2. DNS Resolution - Verifies DNS resolves to expected region's IP ranges
3. Network Latency - Measures latency as proxy for region proximity
4. Response Headers - Checks for any region-indicating headers from load balancer
5. AWS IP Ranges - Validates against AWS published IP ranges

This approach works even if the application doesn't include region information.
"""

import json
import os
import boto3
import urllib3
import socket
import ipaddress
from datetime import datetime
from typing import Dict, Any, Optional, List, Tuple
from urllib.parse import urlparse

# Initialize HTTP client
http = urllib3.PoolManager(
    retries=urllib3.util.Retry(
        total=3,
        backoff_factor=0.3,
        status_forcelist=[500, 502, 503, 504]
    ),
    timeout=urllib3.Timeout(connect=5.0, read=10.0)
)

# Initialize CloudWatch client
cloudwatch = boto3.client('cloudwatch')

# Get configuration from environment variables
APP_DOMAIN = os.environ.get('APP_DOMAIN', 'myapp.kostas.com')
EXPECTED_REGION = os.environ.get('AWS_REGION')
HEALTH_CHECK_PATH = os.environ.get('HEALTH_CHECK_PATH', '/health')
USE_HTTPS = os.environ.get('USE_HTTPS', 'true').lower() == 'true'
USE_IP_GEOLOCATION = os.environ.get('USE_IP_GEOLOCATION', 'true').lower() == 'true'

# AWS Region to IP prefix mapping (simplified - you may want to load from AWS IP ranges)
AWS_REGION_IP_PREFIXES = {
    'us-east-1': ['3.5.140.0/22', '52.0.0.0/15', '52.84.0.0/15', '54.182.0.0/16'],
    'eu-west-1': ['52.16.0.0/15', '52.84.0.0/15', '54.239.0.0/16'],
    'ap-southeast-1': ['13.228.0.0/15', '52.74.0.0/16', '54.251.0.0/16'],
    # Add more regions and IP ranges as needed
    # You can fetch this from: https://ip-ranges.amazonaws.com/ip-ranges.json
}

# Expected latency ranges per region (milliseconds) - adjust based on your testing
EXPECTED_LATENCY_RANGES = {
    'us-east-1': (10, 100),  # Within region
    'eu-west-1': (10, 100),
    'ap-southeast-1': (10, 100),
}


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler function.
    """
    try:
        protocol = 'https' if USE_HTTPS else 'http'
        url = f"{protocol}://{APP_DOMAIN}{HEALTH_CHECK_PATH}"
        
        # Perform multiple verification methods
        results = {
            'timestamp': datetime.utcnow().isoformat(),
            'region': EXPECTED_REGION,
            'url': url,
            'verification_methods': {}
        }
        
        # Method 1: DNS Resolution and IP Geolocation
        dns_result = verify_dns_resolution(APP_DOMAIN, EXPECTED_REGION)
        results['verification_methods']['dns_ip_geolocation'] = dns_result
        
        # Method 2: HTTP Request with IP analysis
        http_result = verify_http_response(url, EXPECTED_REGION)
        results['verification_methods']['http_response'] = http_result
        
        # Method 3: Latency measurement
        latency_result = measure_latency(url, EXPECTED_REGION)
        results['verification_methods']['latency'] = latency_result
        
        # Method 4: Load balancer headers analysis
        headers_result = analyze_response_headers(http_result.get('headers', {}), EXPECTED_REGION)
        results['verification_methods']['headers'] = headers_result
        
        # Overall assessment
        overall_match = assess_overall_match(results['verification_methods'], EXPECTED_REGION)
        results['overall_match'] = overall_match['match']
        results['confidence'] = overall_match['confidence']
        results['reason'] = overall_match['reason']
        
        # Send metrics
        send_metrics(overall_match['match'], EXPECTED_REGION, results)
        
        print(json.dumps(results, indent=2))
        
        if overall_match['match']:
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': 'Health check passed',
                    'result': results
                })
            }
        else:
            return {
                'statusCode': 500,
                'body': json.dumps({
                    'message': 'Health check failed - region verification failed',
                    'result': results
                })
            }
            
    except Exception as e:
        error_result = {
            'timestamp': datetime.utcnow().isoformat(),
            'region': EXPECTED_REGION,
            'error': str(e),
            'success': False
        }
        
        send_metrics(False, EXPECTED_REGION, {'error': True})
        print(json.dumps(error_result, indent=2))
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'message': 'Health check failed with error',
                'result': error_result
            })
        }


def verify_dns_resolution(domain: str, expected_region: str) -> Dict[str, Any]:
    """
    Resolve DNS and check if IP addresses match expected region's IP ranges.
    """
    try:
        # Resolve domain to IP addresses
        ip_addresses = []
        try:
            # Get all A records
            addr_info = socket.getaddrinfo(domain, None, socket.AF_INET)
            ip_addresses = [info[4][0] for info in addr_info]
        except socket.gaierror as e:
            return {
                'success': False,
                'error': f'DNS resolution failed: {str(e)}',
                'match': False
            }
        
        if not ip_addresses:
            return {
                'success': False,
                'error': 'No IP addresses resolved',
                'match': False
            }
        
        # Check if any IP matches expected region's IP ranges
        matches_region = False
        matched_ips = []
        
        if expected_region in AWS_REGION_IP_PREFIXES:
            for ip in ip_addresses:
                ip_obj = ipaddress.ip_address(ip)
                for prefix in AWS_REGION_IP_PREFIXES[expected_region]:
                    if ip_obj in ipaddress.ip_network(prefix, strict=False):
                        matches_region = True
                        matched_ips.append(ip)
                        break
        
        return {
            'success': True,
            'ip_addresses': ip_addresses,
            'matched_ips': matched_ips,
            'match': matches_region,
            'method': 'dns_ip_range_check'
        }
        
    except Exception as e:
        return {
            'success': False,
            'error': str(e),
            'match': False
        }


def verify_http_response(url: str, expected_region: str) -> Dict[str, Any]:
    """
    Make HTTP request and analyze response for region indicators.
    """
    try:
        start_time = datetime.utcnow()
        response = http.request(
            'GET',
            url,
            headers={
                'User-Agent': 'ECS-HealthCheck-Lambda/1.0',
                'Accept': 'application/json'
            }
        )
        end_time = datetime.utcnow()
        latency_ms = (end_time - start_time).total_seconds() * 1000
        
        headers = {k.lower(): v for k, v in response.headers.items()}
        
        # Try to get response IP (if available through headers)
        response_ip = None
        if 'x-forwarded-for' in headers:
            response_ip = headers['x-forwarded-for'].split(',')[0].strip()
        elif 'x-real-ip' in headers:
            response_ip = headers['x-real-ip']
        
        # Check if response IP matches expected region
        ip_match = False
        if response_ip and expected_region in AWS_REGION_IP_PREFIXES:
            try:
                ip_obj = ipaddress.ip_address(response_ip)
                for prefix in AWS_REGION_IP_PREFIXES[expected_region]:
                    if ip_obj in ipaddress.ip_network(prefix, strict=False):
                        ip_match = True
                        break
            except ValueError:
                pass
        
        return {
            'success': True,
            'status_code': response.status,
            'headers': headers,
            'response_ip': response_ip,
            'ip_match': ip_match,
            'latency_ms': latency_ms,
            'match': ip_match  # Can be enhanced with more checks
        }
        
    except Exception as e:
        return {
            'success': False,
            'error': str(e),
            'match': False
        }


def measure_latency(url: str, expected_region: str) -> Dict[str, Any]:
    """
    Measure network latency as a proxy for region proximity.
    Lower latency typically indicates closer region.
    """
    try:
        latencies = []
        for _ in range(3):  # Take 3 measurements
            start_time = datetime.utcnow()
            try:
                response = http.request('GET', url, timeout=urllib3.Timeout(connect=2.0, read=5.0))
                end_time = datetime.utcnow()
                latency_ms = (end_time - start_time).total_seconds() * 1000
                latencies.append(latency_ms)
            except Exception:
                pass
        
        if not latencies:
            return {
                'success': False,
                'error': 'Could not measure latency',
                'match': False
            }
        
        avg_latency = sum(latencies) / len(latencies)
        min_latency = min(latencies)
        max_latency = max(latencies)
        
        # Check if latency is within expected range for the region
        expected_range = EXPECTED_LATENCY_RANGES.get(expected_region, (0, 1000))
        latency_match = expected_range[0] <= avg_latency <= expected_range[1]
        
        return {
            'success': True,
            'average_latency_ms': avg_latency,
            'min_latency_ms': min_latency,
            'max_latency_ms': max_latency,
            'expected_range_ms': expected_range,
            'match': latency_match,
            'method': 'latency_measurement'
        }
        
    except Exception as e:
        return {
            'success': False,
            'error': str(e),
            'match': False
        }


def analyze_response_headers(headers: Dict[str, str], expected_region: str) -> Dict[str, Any]:
    """
    Analyze response headers for any region-indicating information.
    Checks common headers that load balancers/proxies might add.
    """
    region_indicators = {}
    match = False
    
    # Check for common region headers
    region_header_names = [
        'x-amzn-region',
        'x-region',
        'x-served-from-region',
        'x-edge-location',
        'x-cloudfront-region',
        'x-aws-region'
    ]
    
    for header_name in region_header_names:
        if header_name in headers:
            value = headers[header_name].lower()
            region_indicators[header_name] = value
            if expected_region.lower() in value:
                match = True
    
    # Check for AWS-specific headers
    if 'x-amzn-requestid' in headers:
        region_indicators['x-amzn-requestid'] = headers['x-amzn-requestid']
    
    # Check server header for region hints
    if 'server' in headers:
        server_value = headers['server'].lower()
        region_indicators['server'] = server_value
        # Some load balancers include region in server header
    
    return {
        'success': True,
        'region_indicators': region_indicators,
        'match': match,
        'method': 'header_analysis'
    }


def assess_overall_match(verification_methods: Dict[str, Any], expected_region: str) -> Dict[str, Any]:
    """
    Assess overall match based on multiple verification methods.
    Uses weighted scoring for confidence.
    """
    scores = []
    reasons = []
    
    # DNS/IP Geolocation (weight: 0.4)
    dns_result = verification_methods.get('dns_ip_geolocation', {})
    if dns_result.get('match'):
        scores.append(0.4)
        reasons.append('DNS IP matches expected region')
    elif dns_result.get('success'):
        reasons.append('DNS IP does not match expected region')
    
    # HTTP Response IP (weight: 0.3)
    http_result = verification_methods.get('http_response', {})
    if http_result.get('ip_match'):
        scores.append(0.3)
        reasons.append('Response IP matches expected region')
    elif http_result.get('success'):
        reasons.append('Response IP does not match expected region')
    
    # Latency (weight: 0.2)
    latency_result = verification_methods.get('latency', {})
    if latency_result.get('match'):
        scores.append(0.2)
        reasons.append('Latency within expected range')
    elif latency_result.get('success'):
        reasons.append('Latency outside expected range')
    
    # Headers (weight: 0.1)
    headers_result = verification_methods.get('headers', {})
    if headers_result.get('match'):
        scores.append(0.1)
        reasons.append('Headers indicate correct region')
    
    total_score = sum(scores)
    confidence = 'high' if total_score >= 0.7 else 'medium' if total_score >= 0.4 else 'low'
    match = total_score >= 0.5  # Require at least 50% confidence
    
    return {
        'match': match,
        'confidence': confidence,
        'score': total_score,
        'reason': '; '.join(reasons) if reasons else 'No verification methods succeeded'
    }


def send_metrics(match: bool, region: str, results: Dict[str, Any]) -> None:
    """
    Send custom metrics to CloudWatch.
    """
    try:
        namespace = 'ECS/HealthCheck'
        timestamp = datetime.utcnow()
        
        confidence_score = results.get('confidence', 'unknown')
        score_value = results.get('verification_methods', {}).get('overall_match', {}).get('score', 0)
        
        cloudwatch.put_metric_data(
            Namespace=namespace,
            MetricData=[
                {
                    'MetricName': 'HealthCheckStatus',
                    'Dimensions': [
                        {'Name': 'Region', 'Value': region},
                        {'Name': 'Domain', 'Value': APP_DOMAIN}
                    ],
                    'Value': 1 if match else 0,
                    'Unit': 'Count',
                    'Timestamp': timestamp
                },
                {
                    'MetricName': 'HealthCheckConfidence',
                    'Dimensions': [
                        {'Name': 'Region', 'Value': region},
                        {'Name': 'Domain', 'Value': APP_DOMAIN}
                    ],
                    'Value': score_value,
                    'Unit': 'None',
                    'Timestamp': timestamp
                }
            ]
        )
    except Exception as e:
        print(f"Failed to send metrics to CloudWatch: {str(e)}")


def load_aws_ip_ranges() -> Dict[str, List[str]]:
    """
    Load AWS IP ranges from AWS published JSON.
    This is a placeholder - you can enhance this to fetch from:
    https://ip-ranges.amazonaws.com/ip-ranges.json
    """
    # TODO: Implement fetching from AWS IP ranges JSON
    # For now, using hardcoded ranges
    return AWS_REGION_IP_PREFIXES

