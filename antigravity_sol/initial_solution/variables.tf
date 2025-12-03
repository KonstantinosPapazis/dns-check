variable "target_url" {
  description = "The URL to check"
  type        = string
  default     = "https://myapp.kostas.com"
}

variable "region_header" {
  description = "The header that indicates the serving region"
  type        = string
  default     = "X-Region"
}
