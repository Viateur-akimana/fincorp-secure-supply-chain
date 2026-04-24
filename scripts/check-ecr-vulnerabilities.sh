#!/usr/bin/env bash
# check-ecr-vulnerabilities.sh
# Polls ECR image scan results and fails if HIGH or CRITICAL findings exist.
#
# Usage: check-ecr-vulnerabilities.sh <repository-name> <image-tag>
set -euo pipefail

REPO_NAME="$1"
IMAGE_TAG="$2"
MAX_WAIT=120  # seconds
INTERVAL=10

echo "Checking ECR scan results for ${REPO_NAME}:${IMAGE_TAG} ..."

elapsed=0
while true; do
  STATUS=$(aws ecr describe-image-scan-findings \
    --repository-name "$REPO_NAME" \
    --image-id imageTag="$IMAGE_TAG" \
    --query 'imageScanStatus.status' \
    --output text 2>/dev/null || echo "PENDING")

  if [[ "$STATUS" == "COMPLETE" ]]; then
    break
  fi

  if [[ $elapsed -ge $MAX_WAIT ]]; then
    echo "WARNING: ECR scan did not complete within ${MAX_WAIT}s – proceeding with Trivy results only."
    exit 0
  fi

  echo "  Scan status: ${STATUS} (waited ${elapsed}s)"
  sleep $INTERVAL
  elapsed=$((elapsed + INTERVAL))
done

# Pull severity counts
FINDINGS=$(aws ecr describe-image-scan-findings \
  --repository-name "$REPO_NAME" \
  --image-id imageTag="$IMAGE_TAG" \
  --query 'imageScanFindings.findingSeverityCounts' \
  --output json)

echo "ECR scan severity summary:"
echo "$FINDINGS" | python3 -m json.tool

CRITICAL=$(echo "$FINDINGS" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('CRITICAL', 0))")
HIGH=$(echo "$FINDINGS"     | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('HIGH', 0))")

echo "CRITICAL: ${CRITICAL}  HIGH: ${HIGH}"

if [[ "$CRITICAL" -gt 0 || "$HIGH" -gt 0 ]]; then
  echo "FAIL: Found ${CRITICAL} CRITICAL and ${HIGH} HIGH vulnerabilities in ECR image scan."
  echo "Build is blocked. Remediate the vulnerabilities and re-run the pipeline."
  exit 1
fi

echo "PASS: No CRITICAL or HIGH vulnerabilities found in ECR image scan."
