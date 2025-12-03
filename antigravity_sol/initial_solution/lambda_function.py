import json
import urllib.request
import urllib.error
import os
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    url = os.environ.get('TARGET_URL', 'https://myapp.kostas.com')
    expected_header = os.environ.get('REGION_HEADER', 'X-Region')
    current_region = os.environ.get('AWS_REGION')
    
    logger.info(f"Checking URL: {url} from region: {current_region}")
    
    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req) as response:
            status_code = response.getcode()
            headers = dict(response.info())
            
            logger.info(f"Response Status: {status_code}")
            logger.info(f"Response Headers: {json.dumps(headers)}")
            
            served_region = headers.get(expected_header)
            
            if served_region:
                logger.info(f"Application served from region: {served_region}")
                
                return {
                    'statusCode': 200,
                    'body': json.dumps({
                        'message': 'Health check successful',
                        'served_from': served_region,
                        'checked_from': current_region
                    })
                }
            else:
                logger.warning(f"Header {expected_header} not found in response.")
                return {
                    'statusCode': 200,
                    'body': json.dumps({
                        'message': 'Health check successful (header missing)',
                        'checked_from': current_region,
                        'headers_received': list(headers.keys())
                    })
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
