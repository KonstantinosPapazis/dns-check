"""
Lambda function to verify ECS service is being served from the correct region
based on geolocation routing via F5 load balancer.

This function:
1. Makes HTTP requests to the application domain
2. Verifies the response includes region identification
3. Confirms the region matches the expected region for this Lambda
4. Reports results to CloudWatch Metrics
"""

import json
import os
import boto3
import urllib3
from datetime import datetime
from typing import Dict, Any, Optional

# Initialize HTTP client with retries
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
EXPECTED_REGION = os.environ.get('AWS_REGION')  # Set by Lambda runtime
HEALTH_CHECK_PATH = os.environ.get('HEALTH_CHECK_PATH', '/health')
REGION_HEADER = os.environ.get('REGION_HEADER', 'X-Served-From-Region')
USE_HTTPS = os.environ.get('USE_HTTPS', 'true').lower() == 'true'


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler function.
    
    Args:
        event: Event data (can be from EventBridge or manual invocation)
        context: Lambda context object
        
    Returns:
        Dictionary with status code and result details
    """
    try:
        # Determine the protocol
        protocol = 'https' if USE_HTTPS else 'http'
        url = f"{protocol}://{APP_DOMAIN}{HEALTH_CHECK_PATH}"
        
        # Make HTTP request
        response = make_health_check_request(url)
        
        # Verify region
        region_check_result = verify_region(response, EXPECTED_REGION)
        
        # Send metrics to CloudWatch
        send_metrics(region_check_result, EXPECTED_REGION)
        
        # Prepare result
        result = {
            'timestamp': datetime.utcnow().isoformat(),
            'region': EXPECTED_REGION,
            'url': url,
            'status_code': response.get('status_code'),
            'region_match': region_check_result['match'],
            'detected_region': region_check_result.get('detected_region'),
            'expected_region': EXPECTED_REGION,
            'success': region_check_result['match']
        }
        
        # Log result
        print(json.dumps(result, indent=2))
        
        if region_check_result['match']:
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': 'Health check passed',
                    'result': result
                })
            }
        else:
            return {
                'statusCode': 500,
                'body': json.dumps({
                    'message': 'Health check failed - region mismatch',
                    'result': result
                })
            }
            
    except Exception as e:
        error_result = {
            'timestamp': datetime.utcnow().isoformat(),
            'region': EXPECTED_REGION,
            'error': str(e),
            'success': False
        }
        
        # Send failure metric
        send_metrics({'match': False, 'error': True}, EXPECTED_REGION)
        
        print(json.dumps(error_result, indent=2))
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'message': 'Health check failed with error',
                'result': error_result
            })
        }


def make_health_check_request(url: str) -> Dict[str, Any]:
    """
    Make HTTP request to the health check endpoint.
    
    Args:
        url: Full URL to check
        
    Returns:
        Dictionary with response details
    """
    try:
        response = http.request(
            'GET',
            url,
            headers={
                'User-Agent': 'ECS-HealthCheck-Lambda/1.0',
                'Accept': 'application/json'
            }
        )
        
        # Parse response headers
        headers = {k.lower(): v for k, v in response.headers.items()}
        
        # Try to parse JSON response body
        try:
            body = json.loads(response.data.decode('utf-8'))
        except (json.JSONDecodeError, UnicodeDecodeError):
            body = response.data.decode('utf-8', errors='ignore')
        
        return {
            'status_code': response.status,
            'headers': headers,
            'body': body,
            'data': response.data.decode('utf-8', errors='ignore')
        }
        
    except urllib3.exceptions.HTTPError as e:
        raise Exception(f"HTTP request failed: {str(e)}")
    except Exception as e:
        raise Exception(f"Request error: {str(e)}")


def verify_region(response: Dict[str, Any], expected_region: str) -> Dict[str, Any]:
    """
    Verify that the response indicates it came from the expected region.
    
    Checks multiple methods:
    1. Custom header (X-Served-From-Region)
    2. Response body JSON field (region)
    3. Response body JSON field (served_from_region)
    
    Args:
        response: Response dictionary from HTTP request
        expected_region: Expected AWS region code
        
    Returns:
        Dictionary with match status and detected region
    """
    detected_region = None
    
    # Method 1: Check custom header
    headers = response.get('headers', {})
    if REGION_HEADER.lower() in headers:
        detected_region = headers[REGION_HEADER.lower()]
    
    # Method 2: Check response body (if JSON)
    if not detected_region and isinstance(response.get('body'), dict):
        body = response['body']
        # Try common field names
        detected_region = (
            body.get('region') or
            body.get('served_from_region') or
            body.get('aws_region') or
            body.get('deployment_region')
        )
    
    # Method 3: Check response body string (if not JSON)
    if not detected_region:
        data = response.get('data', '')
        # Look for region pattern in response
        import re
        region_pattern = r'(?:region|served_from_region|aws_region)[":\s]+([a-z0-9-]+)'
        match = re.search(region_pattern, data, re.IGNORECASE)
        if match:
            detected_region = match.group(1)
    
    # Normalize region codes (remove common variations)
    if detected_region:
        detected_region = detected_region.strip().lower()
        # Handle common variations
        detected_region = detected_region.replace('_', '-')
    
    expected_normalized = expected_region.lower().strip()
    
    match = detected_region == expected_normalized if detected_region else False
    
    return {
        'match': match,
        'detected_region': detected_region,
        'expected_region': expected_normalized,
        'verification_method': 'header' if REGION_HEADER.lower() in headers else 'body'
    }


def send_metrics(result: Dict[str, Any], region: str) -> None:
    """
    Send custom metrics to CloudWatch.
    
    Args:
        result: Result dictionary from verify_region
        region: AWS region code
    """
    try:
        namespace = 'ECS/HealthCheck'
        timestamp = datetime.utcnow()
        
        # Metric 1: Health check success/failure
        cloudwatch.put_metric_data(
            Namespace=namespace,
            MetricData=[
                {
                    'MetricName': 'HealthCheckStatus',
                    'Dimensions': [
                        {
                            'Name': 'Region',
                            'Value': region
                        },
                        {
                            'Name': 'Domain',
                            'Value': APP_DOMAIN
                        }
                    ],
                    'Value': 1 if result.get('match', False) else 0,
                    'Unit': 'Count',
                    'Timestamp': timestamp
                },
                {
                    'MetricName': 'HealthCheckFailure',
                    'Dimensions': [
                        {
                            'Name': 'Region',
                            'Value': region
                        },
                        {
                            'Name': 'Domain',
                            'Value': APP_DOMAIN
                        }
                    ],
                    'Value': 1 if not result.get('match', False) else 0,
                    'Unit': 'Count',
                    'Timestamp': timestamp
                }
            ]
        )
    except Exception as e:
        print(f"Failed to send metrics to CloudWatch: {str(e)}")

