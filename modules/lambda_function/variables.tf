variable "lambda_config" {
  type = any
}

variable "main_asset" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "security_group_ids" {
  type = list(string)
}
