# ============================================================
# Lambda Blue-Green Module (mirrors ECS blue-green pattern)
# Two separate functions: blue and green
# ALB switches traffic between them
# ============================================================

resource "aws_lambda_function" "blue" {
  for_each      = var.lambda_config
  function_name = "${each.key}-blue"
  package_type  = "Image"
  image_uri     = each.value.blue_image
  role          = aws_iam_role.lambda_exec[each.key].arn
  publish       = true
  memory_size   = each.value.memory_size
  timeout       = each.value.timeout

  vpc_config {
    subnet_ids         = var.subnet_ids
    security_group_ids = var.security_group_ids
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lambda_function" "green" {
  for_each      = var.lambda_config
  function_name = "${each.key}-green"
  package_type  = "Image"
  image_uri     = each.value.green_image
  role          = aws_iam_role.lambda_exec[each.key].arn
  publish       = true
  memory_size   = each.value.memory_size
  timeout       = each.value.timeout

  vpc_config {
    subnet_ids         = var.subnet_ids
    security_group_ids = var.security_group_ids
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lambda_alias" "blue" {
  for_each         = var.lambda_config
  name             = "live"
  function_name    = aws_lambda_function.blue[each.key].function_name
  function_version = aws_lambda_function.blue[each.key].version

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lambda_alias" "green" {
  for_each         = var.lambda_config
  name             = "live"
  function_name    = aws_lambda_function.green[each.key].function_name
  function_version = aws_lambda_function.green[each.key].version

  lifecycle {
    create_before_destroy = true
  }
}

# ============================================================
# IAM
# ============================================================

resource "aws_iam_role" "lambda_exec" {
  for_each           = var.lambda_config
  name               = "lambda_exec_${each.key}"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role_policy.json
}

data "aws_iam_policy_document" "lambda_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  for_each   = var.lambda_config
  role       = aws_iam_role.lambda_exec[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}
