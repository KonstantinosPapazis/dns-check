import json
import urllib.request
import urllib.error
import os
import logging
import socket
import ipaddress

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    url = os.environ.get('TARGET_URL', 'https://myapp.kostas.com')
    expected_header = os.environ.get('REGION_HEADER', 'X-Region')
    expected_cidr = os.environ.get('EXPECTED_CIDR') # Optional
    current_region = os.environ.get('AWS_REGION')
    
    logger.info(f"Checking URL: {url} from region: {current_region}")
    
    try:
        # Extract hostname from URL
        hostname = urllib.parse.urlparse(url).netloc
        resolved_ip = socket.gethostbyname(hostname)
        logger.info(f"Resolved IP for {hostname}: {resolved_ip}")

        # Check CIDR if provided
        cidr_match = None
        if expected_cidr:
            try:
                network = ipaddress.ip_network(expected_cidr)
                ip = ipaddress.ip_address(resolved_ip)
                cidr_match = ip in network
                logger.info(f"IP {resolved_ip} in {expected_cidr}: {cidr_match}")
            except ValueError as e:
                logger.error(f"Invalid CIDR format: {e}")
                cidr_match = "Invalid CIDR"

        req = urllib.request.Request(url)
        with urllib.request.urlopen(req) as response:
            status_code = response.getcode()
            headers = dict(response.info())
            
            logger.info(f"Response Status: {status_code}")
            
            served_region = headers.get(expected_header)
            
            response_body = {
                'message': 'Health check successful',
                'served_from': served_region,
                'checked_from': current_region,
                'resolved_ip': resolved_ip,
                'cidr_match': cidr_match
            }

            if served_region:
                logger.info(f"Application served from region: {served_region}")
            else:
                logger.warning(f"Header {expected_header} not found in response.")
                response_body['message'] = 'Health check successful (header missing)'
                response_body['headers_received'] = list(headers.keys())
            
            return {
                'statusCode': 200,
                'body': json.dumps(response_body)
            }
                
    except urllib.error.URLError as e:
        logger.error(f"Failed to reach application: {e}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'message': 'Health check failed',
                'error': str(e)
            })
        }
    except Exception as e:
        logger.error(f"Unexpected error: {e}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'message': 'Internal error',
                'error': str(e)
            })
        }
