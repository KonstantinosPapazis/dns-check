terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

variable "function_name" {
  type = string
}

variable "role_arn" {
  type = string
}

variable "filename" {
  type = string
}

variable "source_code_hash" {
  type = string
}

variable "target_url" {
  type = string
}

variable "region_header" {
  type = string
}

variable "expected_cidr" {
  type    = string
  default = ""
}

resource "aws_lambda_function" "health_check" {
  filename         = var.filename
  function_name    = var.function_name
  role             = var.role_arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.12"
  timeout          = 10
  source_code_hash = var.source_code_hash

  environment {
    variables = {
      TARGET_URL    = var.target_url
      REGION_HEADER = var.region_header
      EXPECTED_CIDR = var.expected_cidr
    }
  }
}

resource "aws_cloudwatch_event_rule" "schedule" {
  name                = "${var.function_name}-schedule"
  description         = "Schedule for ${var.function_name}"
  schedule_expression = "rate(5 minutes)"
}

resource "aws_cloudwatch_event_target" "target" {
  rule      = aws_cloudwatch_event_rule.schedule.name
  target_id = "lambda"
  arn       = aws_lambda_function.health_check.arn
}

resource "aws_lambda_permission" "allow_cloudwatch" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.health_check.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.schedule.arn
}
