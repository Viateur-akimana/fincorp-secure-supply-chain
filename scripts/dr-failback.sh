#!/usr/bin/env bash
# dr-failback.sh
# Restores traffic back to us-east-1 after the primary region recovers.
# Run after `terraform apply` has re-provisioned the primary RDS instance.
#
# Usage: dr-failback.sh <dr-db-identifier> <primary-db-identifier> [dr-region] [primary-region]
set -euo pipefail

DR_DB_ID="${1:-fincorp-dr-restored}"
PRIMARY_DB_ID="${2:-fincorp-primary}"
DR_REGION="${3:-us-west-2}"
PRIMARY_REGION="${4:-us-east-1}"

START_TIME=$(date +%s)

echo "============================================================"
echo "  DR FAILBACK: Returning to primary region"
echo "  DR DB       : ${DR_DB_ID} (${DR_REGION})"
echo "  Primary DB  : ${PRIMARY_DB_ID} (${PRIMARY_REGION})"
echo "  Started at  : $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "============================================================"

# 1. Verify primary DB is available
echo "[1/6] Verifying primary DB is available in ${PRIMARY_REGION} ..."
PRIMARY_STATUS=$(aws rds describe-db-instances \
  --db-instance-identifier "$PRIMARY_DB_ID" \
  --region "$PRIMARY_REGION" \
  --query 'DBInstances[0].DBInstanceStatus' \
  --output text 2>&1 || echo "NOT_FOUND")

if [[ "$PRIMARY_STATUS" != "available" ]]; then
  echo "ERROR: Primary DB '${PRIMARY_DB_ID}' is not available (status: ${PRIMARY_STATUS})."
  echo "Run 'terraform apply' to re-provision the primary RDS instance first."
  exit 1
fi

PRIMARY_ENDPOINT=$(aws rds describe-db-instances \
  --db-instance-identifier "$PRIMARY_DB_ID" \
  --region "$PRIMARY_REGION" \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text)
echo "  Primary endpoint: ${PRIMARY_ENDPOINT}"

# 2. Get DR DB endpoint
echo "[2/6] Getting DR DB endpoint ..."
DR_ENDPOINT=$(aws rds describe-db-instances \
  --db-instance-identifier "$DR_DB_ID" \
  --region "$DR_REGION" \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text 2>&1 || echo "NOT_FOUND")

if [[ "$DR_ENDPOINT" == "NOT_FOUND" || -z "$DR_ENDPOINT" ]]; then
  echo "ERROR: DR DB '${DR_DB_ID}' not found in ${DR_REGION}."
  exit 1
fi
echo "  DR endpoint: ${DR_ENDPOINT}"

# 3. Get DB credentials from Secrets Manager
echo "[3/6] Retrieving DB credentials from Secrets Manager ..."
SECRET_ARN=$(aws rds describe-db-instances \
  --db-instance-identifier "$PRIMARY_DB_ID" \
  --region "$PRIMARY_REGION" \
  --query 'DBInstances[0].MasterUserSecret.SecretArn' \
  --output text 2>/dev/null || echo "")

if [[ -n "$SECRET_ARN" && "$SECRET_ARN" != "None" ]]; then
  DB_CREDS=$(aws secretsmanager get-secret-value \
    --secret-id "$SECRET_ARN" \
    --region "$PRIMARY_REGION" \
    --query SecretString --output text)
  DB_USER=$(echo "$DB_CREDS" | python3 -c "import sys,json; print(json.load(sys.stdin)['username'])")
  DB_PASS=$(echo "$DB_CREDS" | python3 -c "import sys,json; print(json.load(sys.stdin)['password'])")
  echo "  Credentials retrieved from Secrets Manager."
else
  echo "  WARNING: No Secrets Manager secret found — using DB_USERNAME / DB_PASSWORD env vars."
  DB_USER="${DB_USERNAME:?Set DB_USERNAME env var}"
  DB_PASS="${DB_PASSWORD:?Set DB_PASSWORD env var}"
fi

DB_NAME=$(aws rds describe-db-instances \
  --db-instance-identifier "$PRIMARY_DB_ID" \
  --region "$PRIMARY_REGION" \
  --query 'DBInstances[0].DBName' \
  --output text)

# 4. Dump DR database
echo "[4/6] Dumping DR database (${DR_DB_ID}) ..."
DUMP_FILE="/tmp/fincorp-dr-dump-$(date +%Y%m%d%H%M%S).sql"

if ! command -v pg_dump &>/dev/null; then
  echo "  WARNING: pg_dump not found — skipping data sync."
  echo "  Install postgresql-client and re-run to sync data from DR to primary."
  DATA_SYNCED=false
else
  PGPASSWORD="$DB_PASS" pg_dump \
    -h "$DR_ENDPOINT" \
    -U "$DB_USER" \
    -d "$DB_NAME" \
    -F plain \
    --no-owner \
    --no-acl \
    -f "$DUMP_FILE"
  echo "  Dump written to: ${DUMP_FILE}"
  DATA_SYNCED=true
fi

# 5. Restore dump into primary
if [[ "$DATA_SYNCED" == "true" ]]; then
  echo "[5/6] Restoring dump into primary DB (${PRIMARY_DB_ID}) ..."
  PGPASSWORD="$DB_PASS" psql \
    -h "$PRIMARY_ENDPOINT" \
    -U "$DB_USER" \
    -d "$DB_NAME" \
    -f "$DUMP_FILE"
  rm -f "$DUMP_FILE"
  echo "  Restore complete."
else
  echo "[5/6] SKIPPED – pg_dump not available, data sync not performed."
fi

# 6. Update SSM to point to primary endpoint
echo "[6/6] Updating SSM parameter store ..."
aws ssm put-parameter \
  --name "/fincorp/active/db_endpoint" \
  --value "$PRIMARY_ENDPOINT" \
  --type String \
  --overwrite \
  --region "$PRIMARY_REGION"
echo "  SSM /fincorp/active/db_endpoint → ${PRIMARY_ENDPOINT}"

# Report
END_TIME=$(date +%s)
TOTAL_MIN=$(( (END_TIME - START_TIME) / 60 ))
TOTAL_SEC=$(( (END_TIME - START_TIME) % 60 ))

echo ""
echo "============================================================"
echo "  DR FAILBACK COMPLETE"
echo "  Active DB    : ${PRIMARY_ENDPOINT}"
echo "  Completed at : $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "  Total time   : ${TOTAL_MIN}m ${TOTAL_SEC}s"
echo ""
echo "  Next steps:"
echo "  1. Update application connection string to: ${PRIMARY_ENDPOINT}"
echo "  2. Redeploy application services to pick up new endpoint"
echo "  3. Validate application health checks pass"
echo "  4. Delete DR instance to stop billing:"
echo "     aws rds delete-db-instance --db-instance-identifier ${DR_DB_ID}"
echo "       --skip-final-snapshot --region ${DR_REGION}"
echo "============================================================"
