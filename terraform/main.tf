# ============================================================================
# DNS Check Lambda - Main Configuration
# Multi-region deployment for geolocation routing validation
# ============================================================================

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.0"
    }
  }
}

# ============================================================================
# Provider Configuration for Multi-Region Deployment
# ============================================================================

provider "aws" {
  alias  = "us-east-1"
  region = "us-east-1"
}

provider "aws" {
  alias  = "eu-west-1"
  region = "eu-west-1"
}

provider "aws" {
  alias  = "ap-southeast-1"
  region = "ap-southeast-1"
}

# ============================================================================
# Lambda Deployment Package
# ============================================================================

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda"
  output_path = "${path.module}/.terraform/lambda_function.zip"
}

# ============================================================================
# IAM Role for Lambda (shared across regions)
# ============================================================================

resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "${var.project_name}-lambda-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "cloudwatch:namespace" = "DNS-Check/Geolocation"
          }
        }
      }
    ]
  })
}

# ============================================================================
# Regional Lambda Deployments
# ============================================================================

# US-EAST-1
module "lambda_us_east_1" {
  source = "./modules/regional-lambda"
  count  = var.regions["us-east-1"].enabled ? 1 : 0

  providers = {
    aws = aws.us-east-1
  }

  project_name        = var.project_name
  lambda_zip_path     = data.archive_file.lambda_zip.output_path
  lambda_zip_hash     = data.archive_file.lambda_zip.output_base64sha256
  lambda_role_arn     = aws_iam_role.lambda_role.arn
  target_domain       = var.target_domain
  expected_region     = var.regions["us-east-1"].expected_region
  health_endpoint     = var.health_endpoint
  region_header       = var.region_header
  schedule_expression = var.schedule_expression
  timeout_seconds     = var.timeout_seconds
  memory_size         = var.memory_size
  alarm_enabled       = var.alarm_enabled
  alarm_sns_topic_arn = var.alarm_sns_topic_arn
  tags                = var.tags
}

# EU-WEST-1
module "lambda_eu_west_1" {
  source = "./modules/regional-lambda"
  count  = var.regions["eu-west-1"].enabled ? 1 : 0

  providers = {
    aws = aws.eu-west-1
  }

  project_name        = var.project_name
  lambda_zip_path     = data.archive_file.lambda_zip.output_path
  lambda_zip_hash     = data.archive_file.lambda_zip.output_base64sha256
  lambda_role_arn     = aws_iam_role.lambda_role.arn
  target_domain       = var.target_domain
  expected_region     = var.regions["eu-west-1"].expected_region
  health_endpoint     = var.health_endpoint
  region_header       = var.region_header
  schedule_expression = var.schedule_expression
  timeout_seconds     = var.timeout_seconds
  memory_size         = var.memory_size
  alarm_enabled       = var.alarm_enabled
  alarm_sns_topic_arn = var.alarm_sns_topic_arn
  tags                = var.tags
}

# AP-SOUTHEAST-1
module "lambda_ap_southeast_1" {
  source = "./modules/regional-lambda"
  count  = var.regions["ap-southeast-1"].enabled ? 1 : 0

  providers = {
    aws = aws.ap-southeast-1
  }

  project_name        = var.project_name
  lambda_zip_path     = data.archive_file.lambda_zip.output_path
  lambda_zip_hash     = data.archive_file.lambda_zip.output_base64sha256
  lambda_role_arn     = aws_iam_role.lambda_role.arn
  target_domain       = var.target_domain
  expected_region     = var.regions["ap-southeast-1"].expected_region
  health_endpoint     = var.health_endpoint
  region_header       = var.region_header
  schedule_expression = var.schedule_expression
  timeout_seconds     = var.timeout_seconds
  memory_size         = var.memory_size
  alarm_enabled       = var.alarm_enabled
  alarm_sns_topic_arn = var.alarm_sns_topic_arn
  tags                = var.tags
}

