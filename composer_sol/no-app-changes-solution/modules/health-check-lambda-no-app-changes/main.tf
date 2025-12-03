# Lambda IAM Role
resource "aws_iam_role" "lambda_role" {
  name = "ecs-health-check-lambda-role-${var.region}"

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

  tags = {
    Name        = "ECS Health Check Lambda Role (No App Changes)"
    Environment = "production"
    Region      = var.region
  }
}

# IAM Policy for Lambda
resource "aws_iam_role_policy" "lambda_policy" {
  name = "ecs-health-check-lambda-policy-${var.region}"
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
        Resource = "arn:aws:logs:${var.region}:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "cloudwatch:namespace" = "ECS/HealthCheck"
          }
        }
      }
    ]
  })
}

# Lambda Function
resource "aws_lambda_function" "health_check" {
  filename         = var.lambda_zip_path
  function_name    = "ecs-health-check-no-app-changes-${var.region}"
  role             = aws_iam_role.lambda_role.arn
  handler          = "health_check_no_app_changes.lambda_handler"  # Different handler
  runtime          = "python3.11"
  timeout          = 60  # Increased timeout for multiple checks
  memory_size      = 512  # Increased memory for IP range processing
  source_code_hash = filebase64sha256(var.lambda_zip_path)

  environment {
    variables = {
      APP_DOMAIN          = var.app_domain
      AWS_REGION          = var.region
      HEALTH_CHECK_PATH   = var.health_check_path
      USE_HTTPS           = tostring(var.use_https)
      USE_IP_GEOLOCATION  = "true"
    }
  }

  tags = {
    Name        = "ECS Health Check (No App Changes)"
    Environment = "production"
    Region      = var.region
  }
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${aws_lambda_function.health_check.function_name}"
  retention_in_days = 14

  tags = {
    Name = "ECS Health Check Logs"
    Region = var.region
  }
}

# EventBridge Rule for scheduled execution
resource "aws_cloudwatch_event_rule" "schedule" {
  name                = "ecs-health-check-schedule-no-app-changes-${var.region}"
  description         = "Schedule for ECS health check in ${var.region} (no app changes)"
  schedule_expression = var.schedule_expression

  tags = {
    Name   = "ECS Health Check Schedule"
    Region = var.region
  }
}

# EventBridge Target
resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.schedule.name
  target_id = "TriggerLambda"
  arn       = aws_lambda_function.health_check.arn
}

# Lambda Permission for EventBridge
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.health_check.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.schedule.arn
}

# CloudWatch Alarm for health check failures
resource "aws_cloudwatch_metric_alarm" "health_check_failure" {
  alarm_name          = "ecs-health-check-failure-no-app-changes-${var.region}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HealthCheckStatus"
  namespace           = "ECS/HealthCheck"
  period              = 300
  statistic           = "Average"
  threshold           = 0.5  # Alert if less than 50% success rate
  alarm_description   = "Alert when health check fails in ${var.region} (no app changes)"
  treat_missing_data   = "breaching"
  alarm_actions        = var.alarm_email != "" ? [aws_sns_topic.alerts[0].arn] : []

  dimensions = {
    Region = var.region
    Domain = var.app_domain
  }

  tags = {
    Name   = "ECS Health Check Failure Alarm"
    Region = var.region
  }
}

# SNS Topic for alarms (if email is provided)
resource "aws_sns_topic" "alerts" {
  count = var.alarm_email != "" ? 1 : 0
  name  = "ecs-health-check-alerts-no-app-changes-${var.region}"

  tags = {
    Name   = "ECS Health Check Alerts"
    Region = var.region
  }
}

# SNS Topic Subscription
resource "aws_sns_topic_subscription" "email" {
  count     = var.alarm_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alerts[0].arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

