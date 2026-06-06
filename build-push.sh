#!/bin/bash
set -e

ACCOUNT_ID="863570158116"
REGION="us-east-1"
PROFILE="own"
REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

# Login to ECR
aws ecr get-login-password --region $REGION --profile $PROFILE | docker login --username AWS --password-stdin $REGISTRY

# Create repos if not exist
for repo in nginx-lambda apache-lambda; do
  aws ecr describe-repositories --repository-names $repo --region $REGION --profile $PROFILE 2>/dev/null || \
  aws ecr create-repository --repository-name $repo --region $REGION --profile $PROFILE
done

# Build and push nginx blue (v1)
docker build -t ${REGISTRY}/nginx-lambda:blue docker/nginx-blue/
docker push ${REGISTRY}/nginx-lambda:blue

# Build and push nginx green (v2)
docker build -t ${REGISTRY}/nginx-lambda:green docker/nginx-green/
docker push ${REGISTRY}/nginx-lambda:green

# Build and push nginx yellow (v3)
docker build -t ${REGISTRY}/nginx-lambda:yellow docker/nginx-yellow/
docker push ${REGISTRY}/nginx-lambda:yellow

# Build and push apache blue (v1)
docker build -t ${REGISTRY}/apache-lambda:blue docker/apache-blue/
docker push ${REGISTRY}/apache-lambda:blue

# Build and push apache green (v2)
docker build -t ${REGISTRY}/apache-lambda:green docker/apache-green/
docker push ${REGISTRY}/apache-lambda:green

echo ""
echo "=== Images pushed ==="
echo "nginx-lambda blue:  ${REGISTRY}/nginx-lambda:blue"
echo "nginx-lambda green: ${REGISTRY}/nginx-lambda:green"
echo "apache-lambda blue:  ${REGISTRY}/apache-lambda:blue"
echo "apache-lambda green: ${REGISTRY}/apache-lambda:green"
echo ""
echo "=== For terraform.tfvars ==="
echo "Start with blue image, then change to green to trigger deployment:"
echo "  image_uri = \"${REGISTRY}/nginx-lambda:blue\""
