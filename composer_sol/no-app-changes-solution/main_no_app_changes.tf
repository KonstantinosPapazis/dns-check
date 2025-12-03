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

# Archive Lambda function code (using the no-app-changes version)
# Note: Include both the no-app-changes file and requirements
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_function_no_app_changes.zip"
  
  source {
    content  = file("${path.module}/lambda/health_check_no_app_changes.py")
    filename = "health_check_no_app_changes.py"
  }
  
  source {
    content  = file("${path.module}/lambda/requirements_no_app_changes.txt")
    filename = "requirements.txt"
  }
}

# Create Lambda function in each region (using no-app-changes module)
module "health_check_lambda" {
  source = "./modules/health-check-lambda-no-app-changes"
  
  for_each = toset(var.regions)
  
  app_domain        = var.app_domain
  region            = each.key
  health_check_path = var.health_check_path
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

