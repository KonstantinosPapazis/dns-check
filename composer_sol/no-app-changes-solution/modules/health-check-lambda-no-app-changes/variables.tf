variable "app_domain" {
  description = "Application domain name to check"
  type        = string
}

variable "region" {
  description = "AWS region code"
  type        = string
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
  description = "CloudWatch Events schedule expression"
  type        = string
  default     = "rate(5 minutes)"
}

variable "alarm_email" {
  description = "Email address for CloudWatch alarms"
  type        = string
  default     = ""
}

variable "lambda_zip_path" {
  description = "Path to the Lambda function ZIP file"
  type        = string
}

