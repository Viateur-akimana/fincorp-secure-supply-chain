#!/usr/bin/env bash
# dr-validate.sh
# Validates a restored RDS instance is healthy and accepting connections.
#
# Usage: dr-validate.sh <region> <db-instance-identifier>
set -euo pipefail

DR_REGION="$1"
DB_ID="$2"

echo "Validating DR instance ${DB_ID} in ${DR_REGION} ..."

# Check DB status
STATUS=$(aws rds describe-db-instances \
  --db-instance-identifier "$DB_ID" \
  --region "$DR_REGION" \
  --query 'DBInstances[0].DBInstanceStatus' \
  --output text 2>&1 || echo "NOT_FOUND")

if [[ "$STATUS" != "available" ]]; then
  echo "FAIL: DB instance ${DB_ID} status is '${STATUS}' (expected 'available')."
  exit 1
fi

ENDPOINT=$(aws rds describe-db-instances \
  --db-instance-identifier "$DB_ID" \
  --region "$DR_REGION" \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text)

PORT=$(aws rds describe-db-instances \
  --db-instance-identifier "$DB_ID" \
  --region "$DR_REGION" \
  --query 'DBInstances[0].Endpoint.Port' \
  --output text)

LATEST_RESTORE=$(aws rds describe-db-instances \
  --db-instance-identifier "$DB_ID" \
  --region "$DR_REGION" \
  --query 'DBInstances[0].LatestRestorableTime' \
  --output text)

STORAGE_ENCRYPTED=$(aws rds describe-db-instances \
  --db-instance-identifier "$DB_ID" \
  --region "$DR_REGION" \
  --query 'DBInstances[0].StorageEncrypted' \
  --output text)

echo ""
echo "  Status             : ${STATUS}"
echo "  Endpoint           : ${ENDPOINT}:${PORT}"
echo "  Storage encrypted  : ${STORAGE_ENCRYPTED}"
echo "  Latest restorable  : ${LATEST_RESTORE}"

# Network-level connectivity check (requires pg client in runner)
if command -v pg_isready &>/dev/null; then
  if pg_isready -h "$ENDPOINT" -p "$PORT" -t 10; then
    echo "  Network connectivity: PASS"
  else
    echo "  Network connectivity: FAIL (pg_isready timed out)"
    exit 1
  fi
else
  echo "  Network connectivity: SKIPPED (pg_isready not available)"
fi

echo ""
echo "Validation PASSED for ${DB_ID} in ${DR_REGION}."
