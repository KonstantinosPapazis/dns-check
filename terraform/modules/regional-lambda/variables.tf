# ============================================================================
# Regional Lambda Module - Variables
# ============================================================================

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "lambda_zip_path" {
  description = "Path to the Lambda deployment package"
  type        = string
}

variable "lambda_zip_hash" {
  description = "Base64-encoded SHA256 hash of the Lambda package"
  type        = string
}

variable "lambda_role_arn" {
  description = "ARN of the IAM role for the Lambda function"
  type        = string
}

variable "target_domain" {
  description = "The domain to check"
  type        = string
}

variable "expected_region" {
  description = "The expected region that should be serving requests"
  type        = string
}

variable "health_endpoint" {
  description = "The health endpoint path"
  type        = string
}

variable "region_header" {
  description = "HTTP header containing the serving region"
  type        = string
}

variable "schedule_expression" {
  description = "Schedule expression for running checks"
  type        = string
}

variable "timeout_seconds" {
  description = "Lambda timeout in seconds"
  type        = number
}

variable "memory_size" {
  description = "Lambda memory size in MB"
  type        = number
}

variable "alarm_enabled" {
  description = "Enable CloudWatch alarms"
  type        = bool
}

variable "alarm_sns_topic_arn" {
  description = "SNS topic ARN for alarm notifications"
  type        = string
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
}

