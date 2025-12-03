terraform {
  required_version = ">= 1.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

provider "aws" {
  region = var.primary_region
  
  # Uncomment and configure if using multiple AWS accounts
  # assume_role {
  #   role_arn = "arn:aws:iam::ACCOUNT_ID:role/DeploymentRole"
  # }
}

# Variables
variable "app_domain" {
  description = "Application domain name to check (e.g., myapp.kostas.com)"
  type        = string
  default     = "myapp.kostas.com"
}

variable "regions" {
  description = "List of AWS regions where ECS services are deployed"
  type        = list(string)
  default     = ["us-east-1", "eu-west-1", "ap-southeast-1"]
}

variable "primary_region" {
  description = "Primary AWS region for Terraform state and resources"
  type        = string
  default     = "us-east-1"
}

variable "health_check_path" {
  description = "Path for health check endpoint"
  type        = string
  default     = "/health"
}

variable "region_header" {
  description = "HTTP header name that contains region information"
  type        = string
  default     = "X-Served-From-Region"
}

variable "use_https" {
  description = "Use HTTPS for health checks"
  type        = bool
  default     = true
}

variable "schedule_expression" {
  description = "CloudWatch Events schedule expression for health checks"
  type        = string
  default     = "rate(5 minutes)"
}

variable "alarm_email" {
  description = "Email address for CloudWatch alarms"
  type        = string
  default     = ""
}

# Data source to get current AWS region
data "aws_region" "current" {}

# Archive Lambda function code
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/lambda_function.zip"
  excludes    = ["__pycache__", "*.pyc", ".pytest_cache"]
}

# Provider configurations for each region
# Note: You need to define providers for each region explicitly
# For example, if your regions are us-east-1, eu-west-1, ap-southeast-1:
# Uncomment and modify the provider blocks below based on your actual regions

# provider "aws" {
#   alias  = "us_east_1"
#   region = "us-east-1"
# }

# provider "aws" {
#   alias  = "eu_west_1"
#   region = "eu-west-1"
# }

# provider "aws" {
#   alias  = "ap_southeast_1"
#   region = "ap-southeast-1"
# }

# Create Lambda function in each region
# Note: Update the provider references based on your actual provider aliases
module "health_check_lambda" {
  source = "./modules/health-check-lambda"
  
  for_each = toset(var.regions)
  
  # For now, using default provider - update this based on your provider setup
  # If you have provider aliases, use: providers = { aws = aws.us_east_1 } etc.
  
  app_domain        = var.app_domain
  region            = each.key
  health_check_path = var.health_check_path
  region_header     = var.region_header
  use_https         = var.use_https
  schedule_expression = var.schedule_expression
  alarm_email       = var.alarm_email
  
  lambda_zip_path = data.archive_file.lambda_zip.output_path
}

# Outputs
output "lambda_function_arns" {
  description = "ARNs of Lambda functions in each region"
  value = {
    for k, v in module.health_check_lambda : k => v.lambda_function_arn
  }
}

output "cloudwatch_alarm_names" {
  description = "Names of CloudWatch alarms in each region"
  value = {
    for k, v in module.health_check_lambda : k => v.alarm_name
  }
}

