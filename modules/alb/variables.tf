variable "main_asset" {
  type = string
}

variable "asset_name" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "alb_security_group_id" {
  type = string
}

variable "certificate_arn" {
  type = string
}

variable "lambda_config" {
  type = any
}

variable "lambda_blue_alias_arn" {
  type = map(string)
}

variable "lambda_green_alias_arn" {
  type = map(string)
}

variable "canary_source_ips" {
  type    = list(string)
  default = []
}
