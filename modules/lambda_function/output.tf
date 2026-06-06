output "lambda_blue_alias_arns" {
  value = { for k, v in aws_lambda_alias.blue : k => v.arn }
}

output "lambda_green_alias_arns" {
  value = { for k, v in aws_lambda_alias.green : k => v.arn }
}

