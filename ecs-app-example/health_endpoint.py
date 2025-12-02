"""
Example Health Endpoint for Your ECS Application

Add this endpoint to your ECS application to enable region detection
by the DNS check Lambda.

This example is for a Flask application, but the concept applies to any framework.
"""

import os
from flask import Flask, jsonify, make_response

app = Flask(__name__)

# Get region from environment variable (set in ECS task definition)
AWS_REGION = os.environ.get('AWS_REGION', os.environ.get('AWS_DEFAULT_REGION', 'unknown'))


@app.route('/health')
def health():
    """
    Health endpoint that returns region information.
    
    The DNS check Lambda looks for region info in:
    1. X-Served-By-Region header (preferred)
    2. JSON body fields: region, aws_region, served_by_region, server_region
    """
    response = make_response(jsonify({
        'status': 'healthy',
        'region': AWS_REGION,
        'service': 'myapp',
        'version': os.environ.get('APP_VERSION', '1.0.0')
    }))
    
    # Add region header (this is what the Lambda checks for)
    response.headers['X-Served-By-Region'] = AWS_REGION
    
    return response


@app.route('/health/detailed')
def health_detailed():
    """More detailed health check for debugging."""
    import socket
    
    return jsonify({
        'status': 'healthy',
        'region': AWS_REGION,
        'hostname': socket.gethostname(),
        'environment': {
            'AWS_REGION': AWS_REGION,
            'ECS_CLUSTER': os.environ.get('ECS_CLUSTER', 'unknown'),
            'ECS_TASK_FAMILY': os.environ.get('ECS_TASK_FAMILY', 'unknown'),
        }
    })


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)


# =============================================================================
# NGINX Example (if using NGINX as reverse proxy)
# =============================================================================
"""
Add to your nginx.conf:

server {
    listen 80;
    
    # Add region header to all responses
    add_header X-Served-By-Region $AWS_REGION always;
    
    location /health {
        return 200 '{"status": "healthy", "region": "$AWS_REGION"}';
        add_header Content-Type application/json;
        add_header X-Served-By-Region $AWS_REGION;
    }
    
    location / {
        proxy_pass http://app:8080;
    }
}

Set the environment variable in your ECS task definition or use:
    env AWS_REGION=eu-west-1 nginx -g 'daemon off;'
"""


# =============================================================================
# ECS Task Definition Example (JSON snippet)
# =============================================================================
"""
Add to your ECS task definition:

{
    "containerDefinitions": [
        {
            "name": "myapp",
            "image": "your-ecr-repo/myapp:latest",
            "environment": [
                {
                    "name": "AWS_REGION",
                    "value": "eu-west-1"
                },
                {
                    "name": "AWS_DEFAULT_REGION", 
                    "value": "eu-west-1"
                }
            ],
            ...
        }
    ]
}

Note: AWS_REGION and AWS_DEFAULT_REGION are often automatically set by ECS,
but it's good practice to explicitly set them in your task definition.
"""

