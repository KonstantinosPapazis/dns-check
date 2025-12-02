# ============================================================================
# CloudWatch Dashboard for DNS Check Monitoring
# ============================================================================

resource "aws_cloudwatch_dashboard" "dns_check" {
  dashboard_name = "${var.project_name}-geolocation-monitoring"

  dashboard_body = jsonencode({
    widgets = [
      # Header
      {
        type   = "text"
        x      = 0
        y      = 0
        width  = 24
        height = 1
        properties = {
          markdown = "# 🌍 DNS Geolocation Routing Monitor\nMonitoring geolocation-based routing for **${var.target_domain}**"
        }
      },

      # Overall Success Rate
      {
        type   = "metric"
        x      = 0
        y      = 1
        width  = 8
        height = 6
        properties = {
          title  = "Region Match Success Rate"
          region = "us-east-1"
          metrics = [
            ["DNS-Check/Geolocation", "RegionMatchSuccess", "Domain", var.target_domain, "ProbeRegion", "us-east-1", { label = "US East 1", stat = "Average" }],
            ["...", "eu-west-1", { label = "EU West 1", stat = "Average" }],
            ["...", "ap-southeast-1", { label = "AP Southeast 1", stat = "Average" }]
          ]
          view   = "timeSeries"
          stacked = false
          period = 300
        }
      },

      # Routing Failures
      {
        type   = "metric"
        x      = 8
        y      = 1
        width  = 8
        height = 6
        properties = {
          title  = "Geolocation Routing Failures"
          region = "us-east-1"
          metrics = [
            ["DNS-Check/Geolocation", "GeolocationRoutingFailure", "Domain", var.target_domain, "ProbeRegion", "us-east-1", { label = "US East 1", color = "#d62728" }],
            ["...", "eu-west-1", { label = "EU West 1", color = "#ff7f0e" }],
            ["...", "ap-southeast-1", { label = "AP Southeast 1", color = "#9467bd" }]
          ]
          view   = "timeSeries"
          stacked = true
          period = 300
        }
      },

      # HTTP Check Status
      {
        type   = "metric"
        x      = 16
        y      = 1
        width  = 8
        height = 6
        properties = {
          title  = "HTTP Health Check Status"
          region = "us-east-1"
          metrics = [
            ["DNS-Check/Geolocation", "HTTPCheckSuccess", "Domain", var.target_domain, "ProbeRegion", "us-east-1", { label = "US East 1" }],
            ["...", "eu-west-1", { label = "EU West 1" }],
            ["...", "ap-southeast-1", { label = "AP Southeast 1" }]
          ]
          view   = "timeSeries"
          stacked = false
          period = 300
        }
      },

      # DNS Resolution Status
      {
        type   = "metric"
        x      = 0
        y      = 7
        width  = 12
        height = 4
        properties = {
          title  = "DNS Resolution Success"
          region = "us-east-1"
          metrics = [
            ["DNS-Check/Geolocation", "DNSResolutionSuccess", "Domain", var.target_domain, "ProbeRegion", "us-east-1", { label = "US East 1" }],
            ["...", "eu-west-1", { label = "EU West 1" }],
            ["...", "ap-southeast-1", { label = "AP Southeast 1" }]
          ]
          view   = "singleValue"
          period = 300
        }
      },

      # Recent Failures Summary
      {
        type   = "metric"
        x      = 12
        y      = 7
        width  = 12
        height = 4
        properties = {
          title  = "Total Routing Failures (Last 24h)"
          region = "us-east-1"
          metrics = [
            ["DNS-Check/Geolocation", "GeolocationRoutingFailure", "Domain", var.target_domain, "ProbeRegion", "us-east-1", { label = "US East 1", stat = "Sum" }],
            ["...", "eu-west-1", { label = "EU West 1", stat = "Sum" }],
            ["...", "ap-southeast-1", { label = "AP Southeast 1", stat = "Sum" }]
          ]
          view   = "singleValue"
          period = 86400
        }
      },

      # Lambda Logs
      {
        type   = "log"
        x      = 0
        y      = 11
        width  = 24
        height = 6
        properties = {
          title  = "Recent DNS Check Logs"
          region = "us-east-1"
          query  = <<-EOQ
            SOURCE '/aws/lambda/${var.project_name}-us-east-1'
            | SOURCE '/aws/lambda/${var.project_name}-eu-west-1'
            | SOURCE '/aws/lambda/${var.project_name}-ap-southeast-1'
            | filter @message like /region_match|failure_reason|served_region/
            | fields @timestamp, @message
            | sort @timestamp desc
            | limit 50
          EOQ
        }
      }
    ]
  })
}

