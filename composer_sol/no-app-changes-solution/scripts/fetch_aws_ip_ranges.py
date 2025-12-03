#!/usr/bin/env python3
"""
Script to fetch AWS IP ranges and update the Lambda function.
This ensures the Lambda function has the latest AWS IP ranges for region verification.
"""

import json
import urllib3
import sys
from typing import Dict, List

AWS_IP_RANGES_URL = "https://ip-ranges.amazonaws.com/ip-ranges.json"


def fetch_aws_ip_ranges() -> Dict[str, List[str]]:
    """
    Fetch AWS IP ranges from AWS published JSON.
    
    Returns:
        Dictionary mapping region codes to lists of IP prefixes
    """
    http = urllib3.PoolManager()
    
    try:
        print(f"Fetching AWS IP ranges from {AWS_IP_RANGES_URL}...")
        response = http.request('GET', AWS_IP_RANGES_URL)
        data = json.loads(response.data.decode('utf-8'))
        
        # Filter by region and service (EC2 and AMAZON)
        region_ranges = {}
        
        for prefix in data.get('prefixes', []):
            service = prefix.get('service', '')
            region = prefix.get('region', '')
            ip_prefix = prefix.get('ip_prefix', '')
            
            # Include EC2 and AMAZON services (AMAZON includes all AWS services)
            if service in ['EC2', 'AMAZON'] and ip_prefix:
                if region not in region_ranges:
                    region_ranges[region] = []
                if ip_prefix not in region_ranges[region]:
                    region_ranges[region].append(ip_prefix)
        
        print(f"Found IP ranges for {len(region_ranges)} regions")
        return region_ranges
        
    except Exception as e:
        print(f"Error fetching AWS IP ranges: {e}", file=sys.stderr)
        sys.exit(1)


def generate_python_code(region_ranges: Dict[str, List[str]]) -> str:
    """
    Generate Python code for AWS_REGION_IP_PREFIXES dictionary.
    
    Args:
        region_ranges: Dictionary mapping regions to IP prefixes
        
    Returns:
        Python code as string
    """
    lines = ["AWS_REGION_IP_PREFIXES = {"]
    
    # Sort regions for consistent output
    for region in sorted(region_ranges.keys()):
        prefixes = sorted(region_ranges[region])
        # Format with proper indentation
        lines.append(f"    '{region}': [")
        for prefix in prefixes:
            lines.append(f"        '{prefix}',")
        lines.append("    ],")
    
    lines.append("}")
    
    return "\n".join(lines)


def main():
    """Main function."""
    if len(sys.argv) > 1:
        output_file = sys.argv[1]
    else:
        output_file = None
    
    # Fetch IP ranges
    region_ranges = fetch_aws_ip_ranges()
    
    # Generate Python code
    python_code = generate_python_code(region_ranges)
    
    # Output
    if output_file:
        with open(output_file, 'w') as f:
            f.write(python_code)
        print(f"IP ranges written to {output_file}")
    else:
        print("\n" + "="*60)
        print("AWS Region IP Prefixes (Python Dictionary)")
        print("="*60)
        print(python_code)
        print("\nCopy this into your Lambda function to update AWS_REGION_IP_PREFIXES")
    
    # Print summary
    print("\n" + "="*60)
    print("Summary")
    print("="*60)
    for region in sorted(region_ranges.keys()):
        count = len(region_ranges[region])
        print(f"{region}: {count} IP prefixes")
    
    # Check for common regions
    common_regions = ['us-east-1', 'eu-west-1', 'ap-southeast-1']
    print("\nCommon regions:")
    for region in common_regions:
        if region in region_ranges:
            print(f"  ✓ {region}: {len(region_ranges[region])} prefixes")
        else:
            print(f"  ✗ {region}: Not found")


if __name__ == "__main__":
    main()

