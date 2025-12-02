# ============================================================================
# Regional Lambda Module
# Deploys a DNS check Lambda in a specific AWS region
# ============================================================================

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

data "aws_region" "current" {}

# ============================================================================
# Lambda Function
# ============================================================================

resource "aws_lambda_function" "dns_check" {
  function_name    = "${var.project_name}-${data.aws_region.current.name}"
  filename         = var.lambda_zip_path
  source_code_hash = var.lambda_zip_hash
  handler          = "dns_check.lambda_handler"
  runtime          = "python3.11"
  role             = var.lambda_role_arn
  timeout          = var.timeout_seconds
  memory_size      = var.memory_size

  environment {
    variables = {
      TARGET_DOMAIN   = var.target_domain
      EXPECTED_REGION = var.expected_region
      HEALTH_ENDPOINT = var.health_endpoint
      REGION_HEADER   = var.region_header
      TIMEOUT_SECONDS = tostring(var.timeout_seconds - 5)  # Leave buffer for Lambda overhead
    }
  }

  tags = merge(var.tags, {
    Region = data.aws_region.current.name
  })
}

# ============================================================================
# CloudWatch Log Group
# ============================================================================

resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${aws_lambda_function.dns_check.function_name}"
  retention_in_days = 14

  tags = var.tags
}

# ============================================================================
# EventBridge Scheduled Rule
# ============================================================================

resource "aws_cloudwatch_event_rule" "schedule" {
  name                = "${var.project_name}-schedule-${data.aws_region.current.name}"
  description         = "Trigger DNS check Lambda on schedule"
  schedule_expression = var.schedule_expression

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.schedule.name
  target_id = "dns-check-lambda"
  arn       = aws_lambda_function.dns_check.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.dns_check.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.schedule.arn
}

# ============================================================================
# CloudWatch Alarms
# ============================================================================

resource "aws_cloudwatch_metric_alarm" "routing_failure" {
  count = var.alarm_enabled ? 1 : 0

  alarm_name          = "${var.project_name}-routing-failure-${data.aws_region.current.name}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "GeolocationRoutingFailure"
  namespace           = "DNS-Check/Geolocation"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Geolocation routing failure detected in ${data.aws_region.current.name}"
  treat_missing_data  = "notBreaching"

  dimensions = {
    Domain      = var.target_domain
    ProbeRegion = var.expected_region
  }

  alarm_actions = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []
  ok_actions    = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "http_failure" {
  count = var.alarm_enabled ? 1 : 0

  alarm_name          = "${var.project_name}-http-failure-${data.aws_region.current.name}"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCheckSuccess"
  namespace           = "DNS-Check/Geolocation"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "HTTP health check failing in ${data.aws_region.current.name}"
  treat_missing_data  = "breaching"

  dimensions = {
    Domain      = var.target_domain
    ProbeRegion = var.expected_region
  }

  alarm_actions = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []
  ok_actions    = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []

  tags = var.tags
}

