# ============================================================================
# DNS Check Lambda - Variables
# ============================================================================

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "dns-check"
}

variable "target_domain" {
  description = "The domain to check (e.g., myapp.kostas.com)"
  type        = string
}

variable "health_endpoint" {
  description = "The health/info endpoint that returns region information"
  type        = string
  default     = "/health"
}

variable "region_header" {
  description = "HTTP header name that contains the serving region"
  type        = string
  default     = "X-Served-By-Region"
}

variable "regions" {
  description = "Map of AWS regions to deploy the Lambda and their expected routing"
  type = map(object({
    expected_region = string  # The region the ECS should be serving from
    enabled         = bool    # Whether to deploy in this region
  }))
  default = {
    "us-east-1" = {
      expected_region = "us-east-1"
      enabled         = true
    }
    "eu-west-1" = {
      expected_region = "eu-west-1"
      enabled         = true
    }
    "ap-southeast-1" = {
      expected_region = "ap-southeast-1"
      enabled         = true
    }
  }
}

variable "schedule_expression" {
  description = "CloudWatch Events schedule expression for running checks"
  type        = string
  default     = "rate(5 minutes)"
}

variable "timeout_seconds" {
  description = "Lambda timeout in seconds"
  type        = number
  default     = 30
}

variable "memory_size" {
  description = "Lambda memory size in MB"
  type        = number
  default     = 128
}

variable "alarm_enabled" {
  description = "Enable CloudWatch alarms for routing failures"
  type        = bool
  default     = true
}

variable "alarm_sns_topic_arn" {
  description = "SNS topic ARN to send alarm notifications (optional)"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    ManagedBy = "terraform"
    Purpose   = "dns-geolocation-check"
  }
}

