#!/usr/bin/env bash
# bootstrap-tf-state.sh
# Creates the S3 bucket and DynamoDB table required for Terraform remote state.
# Run ONCE before the first `terraform init` when migrating from local to remote state.
#
# Usage: bash scripts/bootstrap-tf-state.sh [aws-region] [aws-account-id]
set -euo pipefail

REGION="${1:-us-east-1}"
ACCOUNT_ID="${2:-$(aws sts get-caller-identity --query Account --output text)}"
BUCKET_NAME="fincorp-terraform-state-${ACCOUNT_ID}"
TABLE_NAME="fincorp-terraform-locks"

echo "============================================================"
echo "  Bootstrapping Terraform Remote State"
echo "  Bucket : ${BUCKET_NAME}  (${REGION})"
echo "  Table  : ${TABLE_NAME}"
echo "============================================================"

# 1. Create S3 bucket
echo "[1/5] Creating S3 bucket ..."
if aws s3api head-bucket --bucket "$BUCKET_NAME" --region "$REGION" 2>/dev/null; then
  echo "  Bucket already exists – skipping."
else
  aws s3api create-bucket \
    --bucket "$BUCKET_NAME" \
    --region "$REGION" \
    $( [[ "$REGION" != "us-east-1" ]] && echo "--create-bucket-configuration LocationConstraint=$REGION" )
  echo "  Created: ${BUCKET_NAME}"
fi

# 2. Enable versioning
echo "[2/5] Enabling versioning ..."
aws s3api put-bucket-versioning \
  --bucket "$BUCKET_NAME" \
  --versioning-configuration Status=Enabled
echo "  Versioning enabled."

# 3. Enable default encryption (SSE-S3)
echo "[3/5] Enabling default encryption ..."
aws s3api put-bucket-encryption \
  --bucket "$BUCKET_NAME" \
  --server-side-encryption-configuration '{
    "Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]
  }'
echo "  Encryption enabled."

# 4. Block public access
echo "[4/5] Blocking public access ..."
aws s3api put-public-access-block \
  --bucket "$BUCKET_NAME" \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
echo "  Public access blocked."

# 5. Create DynamoDB lock table
echo "[5/5] Creating DynamoDB lock table ..."
if aws dynamodb describe-table --table-name "$TABLE_NAME" --region "$REGION" 2>/dev/null; then
  echo "  Table already exists – skipping."
else
  aws dynamodb create-table \
    --table-name "$TABLE_NAME" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "$REGION"
  echo "  Created: ${TABLE_NAME}"
fi

echo ""
echo "============================================================"
echo "  Bootstrap complete. Next steps:"
echo ""
echo "  1. In infrastructure/terraform/main.tf, replace:"
echo "       backend \"local\" { path = \"terraform.tfstate\" }"
echo "     with:"
echo "       backend \"s3\" {"
echo "         bucket         = \"${BUCKET_NAME}\""
echo "         key            = \"artifact-mgmt/terraform.tfstate\""
echo "         region         = \"${REGION}\""
echo "         encrypt        = true"
echo "         dynamodb_table = \"${TABLE_NAME}\""
echo "       }"
echo ""
echo "  2. Run: terraform init -migrate-state"
echo "============================================================"
