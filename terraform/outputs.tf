# ============================================================================
# DNS Check Lambda - Outputs
# ============================================================================

output "lambda_functions" {
  description = "Lambda functions deployed per region"
  value = {
    us_east_1 = var.regions["us-east-1"].enabled ? {
      arn  = module.lambda_us_east_1[0].lambda_function_arn
      name = module.lambda_us_east_1[0].lambda_function_name
      logs = module.lambda_us_east_1[0].cloudwatch_log_group
    } : null

    eu_west_1 = var.regions["eu-west-1"].enabled ? {
      arn  = module.lambda_eu_west_1[0].lambda_function_arn
      name = module.lambda_eu_west_1[0].lambda_function_name
      logs = module.lambda_eu_west_1[0].cloudwatch_log_group
    } : null

    ap_southeast_1 = var.regions["ap-southeast-1"].enabled ? {
      arn  = module.lambda_ap_southeast_1[0].lambda_function_arn
      name = module.lambda_ap_southeast_1[0].lambda_function_name
      logs = module.lambda_ap_southeast_1[0].cloudwatch_log_group
    } : null
  }
}

output "cloudwatch_dashboard_query" {
  description = "CloudWatch Insights query to view all DNS check results"
  value       = <<-EOT
    fields @timestamp, @message
    | filter @message like /DNS check/
    | sort @timestamp desc
    | limit 100
  EOT
}

output "metric_namespace" {
  description = "CloudWatch metric namespace for DNS check metrics"
  value       = "DNS-Check/Geolocation"
}

