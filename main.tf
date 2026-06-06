terraform {
  backend "s3" {}

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region  = "us-east-1"
  profile = "own"
}

# ============================================================
# VPC
# ============================================================

module "vpc" {
  source     = "./modules/vpc"
  asset_name = var.asset_name
  vpc_cidr   = var.vpc_cidr
}

# ============================================================
# LAMBDA
# ============================================================

module "lambda_func" {
  source              = "./modules/lambda_function"
  lambda_config       = var.lambda_config
  main_asset          = var.main_asset
  subnet_ids          = module.vpc.subnet_ids
  security_group_ids  = [module.vpc.lambda_security_group_id]
}

# ============================================================
# ALB
# ============================================================

module "alb" {
  source                = "./modules/alb"
  lambda_config         = var.lambda_config
  lambda_blue_alias_arn  = module.lambda_func.lambda_blue_alias_arns
  lambda_green_alias_arn = module.lambda_func.lambda_green_alias_arns
  subnet_ids            = module.vpc.subnet_ids
  alb_security_group_id = module.vpc.alb_security_group_id
  main_asset            = var.main_asset
  asset_name            = var.asset_name
  certificate_arn       = var.certificate_arn
  canary_source_ips     = var.canary_source_ips
}

# ============================================================
# OUTPUTS
# ============================================================

output "alb_dns_name" {
  description = "Add this as CNAME in Namecheap for your domains"
  value       = module.alb.alb_dns_name
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "subnet_ids" {
  value = module.vpc.subnet_ids
}
