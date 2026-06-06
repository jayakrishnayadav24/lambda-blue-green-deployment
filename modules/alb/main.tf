resource "aws_lb" "main" {
  name               = "${var.main_asset}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_security_group_id]
  subnets            = var.subnet_ids

  tags = {
    Name = "${var.main_asset}-alb"
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Not Found"
      status_code  = "404"
    }
  }
}

resource "aws_lb_listener" "http_redirect" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# ============================================================
# TARGET GROUPS - Both ALWAYS exist (like ECS blue/green)
# ============================================================

resource "aws_lb_target_group" "blue" {
  for_each    = var.lambda_config
  name        = "${each.value.family}-blue"
  target_type = "lambda"
}

resource "aws_lb_target_group" "green" {
  for_each    = var.lambda_config
  name        = "${each.value.family}-green"
  target_type = "lambda"
}

# ============================================================
# TARGET GROUP ATTACHMENTS - Both ALWAYS attached
# ============================================================

resource "aws_lambda_permission" "blue" {
  for_each      = var.lambda_config
  statement_id  = "AllowALB-${each.key}-blue"
  action        = "lambda:InvokeFunction"
  function_name = "${each.key}-blue"
  qualifier     = "live"
  principal     = "elasticloadbalancing.amazonaws.com"
  source_arn    = aws_lb_target_group.blue[each.key].arn

  depends_on = [aws_lb_target_group.blue]
}

resource "aws_lambda_permission" "green" {
  for_each      = var.lambda_config
  statement_id  = "AllowALB-${each.key}-green"
  action        = "lambda:InvokeFunction"
  function_name = "${each.key}-green"
  qualifier     = "live"
  principal     = "elasticloadbalancing.amazonaws.com"
  source_arn    = aws_lb_target_group.green[each.key].arn

  depends_on = [aws_lb_target_group.green]
}

resource "aws_lb_target_group_attachment" "blue" {
  for_each         = var.lambda_config
  target_group_arn = aws_lb_target_group.blue[each.key].arn
  target_id        = var.lambda_blue_alias_arn[each.key]

  depends_on = [aws_lambda_permission.blue]
}

resource "aws_lb_target_group_attachment" "green" {
  for_each         = var.lambda_config
  target_group_arn = aws_lb_target_group.green[each.key].arn
  target_id        = var.lambda_green_alias_arn[each.key]

  depends_on = [aws_lambda_permission.green]
}

# ============================================================
# LISTENER RULES - Always exist, just switch target group
# ============================================================

locals {
  # Determine which TG serves production traffic
  production_tg = {
    for k, v in var.lambda_config : k => (
      lookup(v, "promote_to_all", false) ? (
        lookup(v, "active_color", "blue") == "blue" ? aws_lb_target_group.green[k].arn : aws_lb_target_group.blue[k].arn
      ) : (
        lookup(v, "active_color", "blue") == "blue" ? aws_lb_target_group.blue[k].arn : aws_lb_target_group.green[k].arn
      )
    )
  }

  # New version TG (for canary)
  new_version_tg = {
    for k, v in var.lambda_config : k => (
      lookup(v, "active_color", "blue") == "blue" ? aws_lb_target_group.green[k].arn : aws_lb_target_group.blue[k].arn
    )
  }
}

# Canary rule - only when activate_canary=true and promote_to_all=false
resource "aws_lb_listener_rule" "canary" {
  for_each = {
    for k, v in var.lambda_config : k => v
    if lookup(v, "activate_canary", false) && !lookup(v, "promote_to_all", false)
  }

  listener_arn = aws_lb_listener.https.arn
  priority     = each.value.priority - 1

  action {
    type             = "forward"
    target_group_arn = local.new_version_tg[each.key]
  }

  condition {
    host_header {
      values = each.value.hostnames
    }
  }

  condition {
    source_ip {
      values = var.canary_source_ips
    }
  }
}

# Production rule - ALWAYS exists
# Uses weighted routing when green_weight > 0, otherwise single TG
resource "aws_lb_listener_rule" "production" {
  for_each     = var.lambda_config
  listener_arn = aws_lb_listener.https.arn
  priority     = each.value.priority

  dynamic "action" {
    for_each = lookup(each.value, "green_weight", 0) > 0 && lookup(each.value, "green_weight", 0) < 100 ? [1] : []
    content {
      type = "forward"
      forward {
        target_group {
          arn    = aws_lb_target_group.blue[each.key].arn
          weight = 100 - lookup(each.value, "green_weight", 0)
        }
        target_group {
          arn    = aws_lb_target_group.green[each.key].arn
          weight = lookup(each.value, "green_weight", 0)
        }
      }
    }
  }

  dynamic "action" {
    for_each = lookup(each.value, "green_weight", 0) == 0 || lookup(each.value, "green_weight", 0) >= 100 ? [1] : []
    content {
      type             = "forward"
      target_group_arn = lookup(each.value, "green_weight", 0) >= 100 ? aws_lb_target_group.green[each.key].arn : local.production_tg[each.key]
    }
  }

  condition {
    host_header {
      values = each.value.hostnames
    }
  }
}
