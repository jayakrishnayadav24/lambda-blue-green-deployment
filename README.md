# Lambda Blue-Green Deployment with Zero Downtime

![Architecture](https://jaya-devto-blog-assets.s3.us-east-1.amazonaws.com/lambda-blue-green/architecture-diagram.png)

A production-ready **zero-downtime blue-green deployment** for AWS Lambda functions using ALB weighted routing — without CodeDeploy, without Route53, without hardcoded VPC/subnet IDs.

## Architecture

```
                    ┌─────────────────────────────────────────┐
                    │           Namecheap DNS                  │
                    │  nginx.jayakrishnayadav.cloud → CNAME    │
                    │  apache.jayakrishnayadav.cloud → CNAME   │
                    └─────────────────┬───────────────────────┘
                                      │
                    ┌─────────────────▼───────────────────────┐
                    │         Application Load Balancer         │
                    │     nginx-dev-fe-alb (HTTPS:443)         │
                    ├──────────────────────────────────────────┤
                    │  Listener Rules:                          │
                    │  ┌─────────────────────────────────────┐ │
                    │  │ Canary Rule (priority-1)             │ │
                    │  │ IF source_ip = your_ip               │ │
                    │  │ → Forward to GREEN TG                │ │
                    │  └─────────────────────────────────────┘ │
                    │  ┌─────────────────────────────────────┐ │
                    │  │ Production Rule (weighted)           │ │
                    │  │ → Blue TG: X%  |  Green TG: Y%      │ │
                    │  └─────────────────────────────────────┘ │
                    └────────────┬──────────────┬──────────────┘
                                 │              │
                    ┌────────────▼────┐  ┌──────▼──────────────┐
                    │  Blue TG        │  │  Green TG            │
                    │  (stable)       │  │  (new version)       │
                    └────────┬────────┘  └──────┬──────────────┘
                             │                  │
                    ┌────────▼────────┐  ┌──────▼──────────────┐
                    │ nginx-lambda-   │  │ nginx-lambda-        │
                    │ blue (v1.0)     │  │ green (v2.0)         │
                    │ BLUE page       │  │ GREEN page           │
                    └─────────────────┘  └─────────────────────┘
```

## Key Features

- **Zero Downtime** — Both blue and green Lambda functions + target groups always exist. ALB just switches traffic — no resource creation/destruction during transitions
- **Weighted Routing** — Gradual traffic shift: 10% → 25% → 50% → 100%
- **IP-Based Canary** — Test new version from your IP before exposing to users
- **No CodeDeploy** — Pure Terraform + ALB listener rules
- **No Route53** — Works with Namecheap or any DNS provider (CNAME)
- **No Hardcoded VPC** — VPC, subnets, security groups created via Terraform outputs
- **Instant Rollback** — Set `green_weight=0` and apply

## Project Structure

```
lambda-blue-green/
└── lambda/
    ├── main.tf                    # Root module wiring
    ├── variables.tf               # Root variables
    ├── env/
    │   └── dev/
    │       ├── backend.hcl        # S3 backend config
    │       └── terraform.tfvars   # All deployment config
    ├── modules/
    │   ├── vpc/                   # Creates VPC, subnets, SGs
    │   ├── alb/                   # ALB, listeners, rules, permissions
    │   └── lambda_function/       # Blue + Green Lambda functions
    ├── docker/
    │   ├── nginx-blue/            # Blue Lambda container image
    │   ├── nginx-green/           # Green Lambda container image
    │   ├── apache-blue/           # Blue Lambda container image
    │   └── apache-green/          # Green Lambda container image
    └── build-push.sh             # Build & push images to ECR
```

## How It Works

### The ECS-Inspired Pattern

This follows the same pattern as ECS blue-green deployments:

| ECS | Lambda (this project) |
|-----|----------------------|
| Blue ECS Service | `nginx-lambda-blue` function |
| Green ECS Service | `nginx-lambda-green` function |
| Blue Target Group | `nginx-svc-blue` TG |
| Green Target Group | `nginx-svc-green` TG |
| ALB rule switches TG | ALB rule switches TG |

Both functions and both target groups **always exist**. The ALB listener rule simply changes which target group receives traffic. No resources are created or destroyed during deployment = **zero downtime**.

### Why Previous Approaches Failed (503 errors)

| Approach | Problem |
|----------|---------|
| Single function + alias switching | TG attachment destroyed/recreated = 503 gap |
| Conditional TG creation (`count`/`for_each`) | TG destroyed before rule switches = 503 |
| Permission timing | Permission not ready when TG attachment created = 403→503 |

### The Solution

- **Two Lambda functions** per service (blue + green) — always deployed
- **Two target groups** per service — always attached with valid targets
- **ALB weighted forward** — just changes weight percentages, no TG changes
- **Canary rule** — higher priority rule that only creates/destroys (safe because production rule catches all traffic)

## Deployment Workflow

### Initial Setup

```bash
# 1. Build and push container images
./build-push.sh

# 2. Initialize Terraform
terraform init -backend-config=env/dev/backend.hcl

# 3. Deploy (both blue and green functions created)
terraform apply -var-file=env/dev/terraform.tfvars
```

### Zero-Downtime Deployment Steps

```
┌─────────────────────────────────────────────────────────────┐
│ Step 1: Normal State                                         │
│   activate_canary = false                                    │
│   green_weight    = 0                                        │
│   → 100% BLUE for everyone                                  │
├─────────────────────────────────────────────────────────────┤
│ Step 2: Canary Test (IP-based)                               │
│   activate_canary = true                                     │
│   green_weight    = 0                                        │
│   → Your IP sees GREEN, everyone else sees BLUE              │
├─────────────────────────────────────────────────────────────┤
│ Step 3: Weighted Rollout                                     │
│   activate_canary = false                                    │
│   green_weight    = 10  (then 25, 50, 75...)                 │
│   → X% of ALL traffic sees GREEN                            │
├─────────────────────────────────────────────────────────────┤
│ Step 4: Full Promotion                                       │
│   green_weight    = 100                                      │
│   → 100% GREEN for everyone                                 │
├─────────────────────────────────────────────────────────────┤
│ Rollback (instant):                                          │
│   green_weight    = 0                                        │
│   activate_canary = false                                    │
│   → Back to 100% BLUE instantly                             │
└─────────────────────────────────────────────────────────────┘
```

### terraform.tfvars Configuration

```hcl
lambda_config = {
  nginx-lambda = {
    family          = "nginx-svc"
    blue_image      = "863570158116.dkr.ecr.us-east-1.amazonaws.com/nginx-lambda:blue"
    green_image     = "863570158116.dkr.ecr.us-east-1.amazonaws.com/nginx-lambda:green"
    memory_size     = 2048
    timeout         = 300
    priority        = 200
    hostnames       = ["nginx.jayakrishnayadav.cloud"]
    active_color    = "blue"
    activate_canary = false
    promote_to_all  = false
    green_weight    = 0       # 0=all blue, 10/25/50/75=weighted, 100=all green
  }
}
```

## Deploying a New Version (v3)

After green is promoted and stable, to deploy v3:

```hcl
# Green (v2) is now stable, make it the new blue:
blue_image  = ".../nginx-lambda:green"   # v2 becomes stable blue
green_image = ".../nginx-lambda:v3"      # new version
green_weight = 0                          # start fresh
activate_canary = true                    # test v3 with your IP
```

Then repeat the workflow: canary → weighted → promote.

## DNS Setup (Namecheap)

After `terraform apply`, grab the ALB DNS from output:

```
alb_dns_name = "nginx-dev-fe-alb-548984355.us-east-1.elb.amazonaws.com"
```

In Namecheap DNS settings:

| Type | Host | Value |
|------|------|-------|
| CNAME | nginx | nginx-dev-fe-alb-548984355.us-east-1.elb.amazonaws.com |
| CNAME | apache | nginx-dev-fe-alb-548984355.us-east-1.elb.amazonaws.com |

## ACM Certificate

Using wildcard cert `*.jayakrishnayadav.cloud`:

```
ARN: arn:aws:acm:us-east-1:863570158116:certificate/abd4cdd8-6bcc-4d10-adda-13ac331c8372
```

Validated via CNAME in Namecheap DNS.

## Testing

Run this curl loop while applying changes to verify zero downtime:

```bash
for i in {1..1000}; do
  for url in \
    "https://nginx.jayakrishnayadav.cloud/" \
    "https://apache.jayakrishnayadav.cloud/"
  do
    response=$(curl -k -s -w " HTTPSTATUS:%{http_code}" "$url")
    body=${response% HTTPSTATUS:*}
    status=${response##*HTTPSTATUS:}

    if [[ $body == *"BLUE - v"* ]]; then
      color="BLUE"
    elif [[ $body == *"GREEN - v"* ]]; then
      color="GREEN"
    else
      color="UNKNOWN"
    fi

    echo "Run: $i | URL: $url | Status: $status | Version: $color"
  done
  sleep 1
done
```

### Expected Results

**Step 1: Canary activation (activate_canary=true):**

![Canary Config](https://jaya-devto-blog-assets.s3.us-east-1.amazonaws.com/lambda-blue-green/canary-config.png)
*Terraform configuration — only activate_canary changed to true*

![Canary Test](https://jaya-devto-blog-assets.s3.us-east-1.amazonaws.com/lambda-blue-green/canary-ip-test.png)
*Canary IP sees GREEN while all other users stay on BLUE — zero 503 errors*

**Step 2: Weighted 50/50 (green_weight=50):**

![Weighted Config](https://jaya-devto-blog-assets.s3.us-east-1.amazonaws.com/lambda-blue-green/weighted-50-config.png)
*Terraform configuration — green_weight set to 50*

![Weighted 50/50](https://jaya-devto-blog-assets.s3.us-east-1.amazonaws.com/lambda-blue-green/weighted-50-50.png)
*Traffic split evenly between blue and green — gradual rollout in action*

**Step 3: Full promotion (green_weight=100):**

![Full Promotion Config](https://jaya-devto-blog-assets.s3.us-east-1.amazonaws.com/lambda-blue-green/full-promotion-config.png)
*Terraform configuration — green_weight set to 100*

![Full Promotion](https://jaya-devto-blog-assets.s3.us-east-1.amazonaws.com/lambda-blue-green/full-promotion-green.png)
*100% traffic shifted to green — zero downtime, no 503s*

**Step 4: Instant Rollback (green_weight=0):**

![Rollback Config](https://jaya-devto-blog-assets.s3.us-east-1.amazonaws.com/lambda-blue-green/rollback-config.png)
*Terraform configuration — green_weight back to 0*

![Instant Rollback](https://jaya-devto-blog-assets.s3.us-east-1.amazonaws.com/lambda-blue-green/instant-rollback.png)
*Instant rollback from green to blue — single terraform apply, zero downtime*

**Step 5: New version deployment (v3 - Yellow):**

![Yellow Config](https://jaya-devto-blog-assets.s3.us-east-1.amazonaws.com/lambda-blue-green/yellow-v3-config.png)
*Terraform configuration — rotated images, green_image now points to yellow (v3)*

![Yellow v3 Deploy](https://jaya-devto-blog-assets.s3.us-east-1.amazonaws.com/lambda-blue-green/yellow-v3-canary.png)
*Deploying v3 (yellow) after v2 (green) was promoted — same workflow repeats*

**Zero 503s in all transitions.**

## Infrastructure Created

| Resource | Purpose |
|----------|---------|
| VPC + 2 Public Subnets | Network in us-east-1 |
| Internet Gateway + Route Table | Public internet access |
| ALB Security Group | Allows 80/443 inbound |
| Lambda Security Group | Egress-only for Lambda VPC |
| Application Load Balancer | HTTPS termination + routing |
| HTTPS Listener (443) | TLS with ACM cert |
| HTTP Listener (80) | Redirects to HTTPS |
| 2 Target Groups per service | Blue + Green (always exist) |
| 2 Lambda Functions per service | Blue + Green (always deployed) |
| IAM Roles + Policies | Lambda execution + VPC access |
| Lambda Permissions | ALB → Lambda invocation |

## Cost Optimization

- Lambda functions only cost when invoked (pay-per-request)
- Both blue and green exist but idle green costs nothing
- ALB: ~$16/month base + per-request charges
- No NAT Gateway needed (Lambda in public subnets for this demo)

## Deploying Subsequent Versions (v3, v4, v5...)

After promoting green (v2) to 100%, here's how to deploy the next version:

### The Pattern: Rotate Images

The key principle: **blue = current stable, green = new version being tested**. After each promotion, the promoted green becomes the new blue.

```
┌─────────────────────────────────────────────────────────────┐
│ Initial State:                                               │
│   blue_image  = nginx-lambda:blue   (v1 - stable)           │
│   green_image = nginx-lambda:green  (v2 - new)              │
│   green_weight = 0                                           │
│   → Everyone sees v1 (BLUE)                                 │
├─────────────────────────────────────────────────────────────┤
│ After promoting v2 (green_weight=100):                       │
│   → Everyone sees v2 (GREEN)                                │
├─────────────────────────────────────────────────────────────┤
│ Deploy v3 (YELLOW):                                          │
│   blue_image  = nginx-lambda:green  (v2 - now stable)       │
│   green_image = nginx-lambda:yellow (v3 - new)              │
│   green_weight = 0                                           │
│   → Everyone sees v2 (now served by blue function)          │
│   → Canary/weighted to test v3                              │
├─────────────────────────────────────────────────────────────┤
│ After promoting v3 (green_weight=100):                       │
│   → Everyone sees v3 (YELLOW)                               │
├─────────────────────────────────────────────────────────────┤
│ Deploy v4:                                                   │
│   blue_image  = nginx-lambda:yellow (v3 - now stable)       │
│   green_image = nginx-lambda:v4     (v4 - new)              │
│   green_weight = 0                                           │
│   → Repeat the cycle...                                     │
└─────────────────────────────────────────────────────────────┘
```

### Step-by-Step Example: v2 → v3 (Yellow)

**1. Build and push new image:**
```bash
docker build -t 863570158116.dkr.ecr.us-east-1.amazonaws.com/nginx-lambda:yellow docker/nginx-yellow/
docker push 863570158116.dkr.ecr.us-east-1.amazonaws.com/nginx-lambda:yellow
```

**2. Update terraform.tfvars — rotate images:**
```hcl
nginx-lambda = {
  family          = "nginx-svc"
  blue_image      = ".../nginx-lambda:green"    # v2 becomes stable blue
  green_image     = ".../nginx-lambda:yellow"   # v3 is new green
  active_color    = "blue"
  activate_canary = true                         # test with your IP first
  green_weight    = 0
}
```

**3. Apply and test canary:**
```bash
terraform apply -var-file=env/dev/terraform.tfvars
# Your IP sees YELLOW (v3), everyone else sees GREEN (v2)
```

**4. Weighted rollout:**
```hcl
activate_canary = false
green_weight    = 10    # 10% yellow, 90% green
```
```bash
terraform apply -var-file=env/dev/terraform.tfvars
```

**5. Increase weight gradually:**
```hcl
green_weight = 50    # 50/50
# then
green_weight = 100   # 100% yellow
```

**6. Rollback anytime:**
```hcl
green_weight    = 0
activate_canary = false
# → Instantly back to v2 (green), zero downtime
```

### Multiple Services — Independent Deployments

Each service in `lambda_config` is deployed independently:

```hcl
lambda_config = {
  # Service 1: Already on v3 (yellow)
  nginx-lambda = {
    family          = "nginx-svc"
    blue_image      = ".../nginx-lambda:green"     # v2 stable
    green_image     = ".../nginx-lambda:yellow"    # v3 testing
    active_color    = "blue"
    activate_canary = false
    green_weight    = 50                            # 50% on v3
  }

  # Service 2: Still on v1, deploying v2
  apache-lambda = {
    family          = "apache-svc"
    blue_image      = ".../apache-lambda:blue"     # v1 stable
    green_image     = ".../apache-lambda:green"    # v2 testing
    active_color    = "blue"
    activate_canary = true                          # canary testing
    green_weight    = 0
  }

  # Service 3: Stable, no deployment in progress
  auth-lambda = {
    family          = "auth-svc"
    blue_image      = ".../auth-lambda:v5"         # current stable
    green_image     = ".../auth-lambda:v5"         # same image = no change
    active_color    = "blue"
    activate_canary = false
    green_weight    = 0                             # 100% blue
  }
}
```

### Quick Reference — All Deployment States

| State | `activate_canary` | `green_weight` | Result |
|-------|:-:|:-:|--------|
| Stable (blue only) | `false` | `0` | 100% blue |
| Canary (IP test) | `true` | `0` | Your IP → green, others → blue |
| 10% rollout | `false` | `10` | 10% green, 90% blue |
| 25% rollout | `false` | `25` | 25% green, 75% blue |
| 50/50 | `false` | `50` | 50% green, 50% blue |
| 75% rollout | `false` | `75` | 75% green, 25% blue |
| Full promotion | `false` | `100` | 100% green |
| Rollback | `false` | `0` | Back to 100% blue instantly |

### CI/CD Integration Example

```bash
#!/bin/bash
# deploy.sh - Automated deployment pipeline
SERVICE=$1
NEW_IMAGE=$2
CURRENT_STABLE=$(grep "green_image" env/dev/terraform.tfvars | grep $SERVICE | awk -F'"' '{print $2}')

# Rotate: current green → blue, new image → green
sed -i "s|blue_image.*$SERVICE.*|blue_image = \"$CURRENT_STABLE\"|" env/dev/terraform.tfvars
sed -i "s|green_image.*$SERVICE.*|green_image = \"$NEW_IMAGE\"|" env/dev/terraform.tfvars

# Canary first
sed -i "s/activate_canary = false/activate_canary = true/" env/dev/terraform.tfvars
terraform apply -var-file=env/dev/terraform.tfvars -auto-approve

# Wait and check health
sleep 30
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" https://$SERVICE.jayakrishnayadav.cloud/)
if [ "$HTTP_CODE" != "200" ]; then
  echo "CANARY FAILED - rolling back"
  sed -i "s/activate_canary = true/activate_canary = false/" env/dev/terraform.tfvars
  terraform apply -var-file=env/dev/terraform.tfvars -auto-approve
  exit 1
fi

# Gradual rollout
for weight in 10 50 100; do
  sed -i "s/green_weight.*=.*/green_weight = $weight/" env/dev/terraform.tfvars
  sed -i "s/activate_canary = true/activate_canary = false/" env/dev/terraform.tfvars
  terraform apply -var-file=env/dev/terraform.tfvars -auto-approve
  sleep 60
done

echo "Deployment complete: $SERVICE → $NEW_IMAGE"
```

## Comparison with AWS CodeDeploy

| Feature | This Approach | CodeDeploy |
|---------|--------------|------------|
| Weighted routing | ✅ Any % | ✅ Linear/Canary |
| IP-based canary | ✅ | ❌ |
| Instant rollback | ✅ | ⚠️ Depends on hooks |
| No extra service | ✅ | ❌ Needs CodeDeploy |
| Full control | ✅ | ⚠️ Limited |
| Terraform native | ✅ | ⚠️ Complex integration |
| Multi-service | ✅ | ⚠️ Per-function config |
