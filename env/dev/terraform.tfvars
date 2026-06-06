# ============================================================
# LAMBDA BLUE-GREEN DEPLOYMENT - ZERO DOWNTIME
#
# WORKFLOW:
# ─────────────────────────────────────────────────────────────
# Step 1: Normal (blue serving production)
#   activate_canary=false, promote_to_all=false, green_weight=0
#   → Everyone sees BLUE.
#
# Step 2: Canary IP test (activate_canary=true)
#   → Only your IP sees GREEN, everyone else sees BLUE.
#
# Step 3: Weighted rollout (green_weight=10/25/50/75)
#   → X% of ALL traffic goes to GREEN, rest to BLUE.
#
# Step 4: Full promote (promote_to_all=true OR green_weight=100)
#   → ALL traffic goes to GREEN.
#
# Rollback: green_weight=0, activate_canary=false, promote_to_all=false
#   → Back to BLUE instantly.
# ─────────────────────────────────────────────────────────────
# ============================================================

main_asset      = "nginx-dev-fe"
asset_name      = "nginx-dev"
certificate_arn = "arn:aws:acm:us-east-1:863570158116:certificate/abd4cdd8-6bcc-4d10-adda-13ac331c8372"

canary_source_ips = ["160.30.39.198/32"]

lambda_config = {
  nginx-lambda = {
    family          = "nginx-svc"
    blue_image      = "863570158116.dkr.ecr.us-east-1.amazonaws.com/nginx-lambda:green"
    green_image     = "863570158116.dkr.ecr.us-east-1.amazonaws.com/nginx-lambda:yellow"
    memory_size     = 2048
    timeout         = 300
    priority        = 200
    hostnames       = ["nginx.jayakrishnayadav.cloud"]
    active_color    = "blue"
    activate_canary = true
    promote_to_all  = false
    green_weight    = 0
  }
  apache-lambda = {
    family          = "apache-svc"
    blue_image      = "863570158116.dkr.ecr.us-east-1.amazonaws.com/apache-lambda:blue"
    green_image     = "863570158116.dkr.ecr.us-east-1.amazonaws.com/apache-lambda:green"
    memory_size     = 1024
    timeout         = 300
    priority        = 201
    hostnames       = ["apache.jayakrishnayadav.cloud"]
    active_color    = "blue"
    activate_canary = false
    promote_to_all  = false
    green_weight    = 0
  }
}
