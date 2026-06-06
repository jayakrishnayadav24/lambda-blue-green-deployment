variable "lambda_config" {
  description = "Lambda function configuration with blue-green deployment"
  type        = any
}

variable "main_asset" {
  type = string
}

variable "asset_name" {
  type = string
}

variable "certificate_arn" {
  type = string
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "canary_source_ips" {
  description = "Source IPs that see the new version during canary (CIDR format)"
  type        = list(string)
  default     = []
}
