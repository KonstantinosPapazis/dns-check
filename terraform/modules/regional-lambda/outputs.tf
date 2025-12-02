# ============================================================================
# Regional Lambda Module - Outputs
# ============================================================================

output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.dns_check.arn
}

output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.dns_check.function_name
}

output "cloudwatch_log_group" {
  description = "CloudWatch Log Group name"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

output "event_rule_arn" {
  description = "ARN of the EventBridge rule"
  value       = aws_cloudwatch_event_rule.schedule.arn
}

