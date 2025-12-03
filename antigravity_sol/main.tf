terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
  alias  = "us_east_1"
}

provider "aws" {
  region = "eu-central-1"
  alias  = "eu_central_1"
}

provider "aws" {
  region = "ap-southeast-2"
  alias  = "ap_southeast_2"
}



# Zip the lambda code
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda_function.py"
  output_path = "${path.module}/lambda_function.zip"
}

# IAM Role (Global/Regional - IAM is global but needs to be referenced)
resource "aws_iam_role" "lambda_role" {
  name = "geo_health_check_lambda_role"

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
}

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Module for deploying Lambda in a specific region
module "health_check_us_east_1" {
  source = "./modules/health_check"
  providers = {
    aws = aws.us_east_1
  }

  function_name    = "geo-health-check-us-east-1"
  role_arn         = aws_iam_role.lambda_role.arn
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  target_url    = var.target_url
  region_header = var.region_header
  expected_cidr = var.expected_cidr
}

module "health_check_eu_central_1" {
  source = "./modules/health_check"
  providers = {
    aws = aws.eu_central_1
  }

  function_name    = "geo-health-check-eu-central-1"
  role_arn         = aws_iam_role.lambda_role.arn
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  target_url    = var.target_url
  region_header = var.region_header
  expected_cidr = var.expected_cidr
}

module "health_check_ap_southeast_2" {
  source = "./modules/health_check"
  providers = {
    aws = aws.ap_southeast_2
  }

  function_name    = "geo-health-check-ap-southeast-2"
  role_arn         = aws_iam_role.lambda_role.arn
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  target_url    = var.target_url
  region_header = var.region_header
}
