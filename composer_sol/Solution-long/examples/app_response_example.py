"""
Example: How to modify your ECS application to include region information
in health check responses.

This example shows how to add region identification to your application's
health check endpoint so the Lambda functions can verify correct routing.
"""

# Example 1: Flask/Python application
from flask import Flask, jsonify
import os

app = Flask(__name__)

@app.route('/health')
def health_check():
    """
    Health check endpoint that includes region information.
    
    The Lambda function will check for the 'region' field in the JSON response
    or the 'X-Served-From-Region' header.
    """
    # Get region from environment variable (set in ECS task definition)
    aws_region = os.environ.get('AWS_REGION', 'unknown')
    
    return jsonify({
        'status': 'healthy',
        'region': aws_region,
        'served_from_region': aws_region,  # Alternative field name
        'timestamp': datetime.utcnow().isoformat()
    }), 200, {
        'X-Served-From-Region': aws_region,  # Header approach
        'Content-Type': 'application/json'
    }


# Example 2: Express.js/Node.js application
"""
const express = require('express');
const app = express();

app.get('/health', (req, res) => {
    const awsRegion = process.env.AWS_REGION || 'unknown';
    
    res.setHeader('X-Served-From-Region', awsRegion);
    res.json({
        status: 'healthy',
        region: awsRegion,
        served_from_region: awsRegion,
        timestamp: new Date().toISOString()
    });
});
"""


# Example 3: ECS Task Definition modification
"""
{
    "family": "myapp-task",
    "containerDefinitions": [
        {
            "name": "myapp",
            "image": "myapp:latest",
            "environment": [
                {
                    "name": "AWS_REGION",
                    "value": "us-east-1"  # Set this per region deployment
                }
            ],
            "portMappings": [
                {
                    "containerPort": 8080
                }
            ]
        }
    ]
}
"""


# Example 4: Using AWS SDK to get region dynamically
"""
import boto3

def get_current_region():
    # Try to get region from metadata service
    try:
        session = boto3.Session()
        return session.region_name
    except:
        # Fallback to environment variable
        return os.environ.get('AWS_REGION', 'unknown')
"""

