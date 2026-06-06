output "alb_dns_name" {
  value = aws_lb.main.dns_name
}

output "blue_target_group_arns" {
  value = { for k, v in aws_lb_target_group.blue : k => v.arn }
}

output "green_target_group_arns" {
  value = { for k, v in aws_lb_target_group.green : k => v.arn }
}
