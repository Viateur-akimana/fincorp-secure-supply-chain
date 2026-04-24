#!/usr/bin/env bash
# dr-simulate-failure.sh
# Simulates an us-east-1 region failure by deleting the primary RDS instance.
# This is a DESTRUCTIVE operation and requires explicit confirmation.
#
# Usage: dr-simulate-failure.sh <db-instance-identifier> <region>
set -euo pipefail

DB_IDENTIFIER="$1"
REGION="${2:-us-east-1}"

echo "============================================================"
echo "  DR SIMULATION: Deleting primary RDS instance"
echo "  Instance : ${DB_IDENTIFIER}"
echo "  Region   : ${REGION}"
echo "  Time     : $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "============================================================"

# Confirm the instance exists
STATUS=$(aws rds describe-db-instances \
  --db-instance-identifier "$DB_IDENTIFIER" \
  --region "$REGION" \
  --query 'DBInstances[0].DBInstanceStatus' \
  --output text 2>&1 || echo "NOT_FOUND")

if [[ "$STATUS" == "NOT_FOUND" ]]; then
  echo "ERROR: DB instance ${DB_IDENTIFIER} not found in ${REGION}."
  exit 1
fi

echo "Current status: ${STATUS}"

# Remove deletion protection before deleting
echo "Disabling deletion protection ..."
aws rds modify-db-instance \
  --db-instance-identifier "$DB_IDENTIFIER" \
  --region "$REGION" \
  --no-deletion-protection \
  --apply-immediately

echo "Waiting for modification to complete ..."
aws rds wait db-instance-available \
  --db-instance-identifier "$DB_IDENTIFIER" \
  --region "$REGION"

# Take a final manual snapshot before deletion
SNAPSHOT_ID="${DB_IDENTIFIER}-pre-dr-drill-$(date +%Y%m%d%H%M%S)"
echo "Creating final snapshot: ${SNAPSHOT_ID} ..."
aws rds create-db-snapshot \
  --db-instance-identifier "$DB_IDENTIFIER" \
  --db-snapshot-identifier "$SNAPSHOT_ID" \
  --region "$REGION"

aws rds wait db-snapshot-completed \
  --db-snapshot-identifier "$SNAPSHOT_ID" \
  --region "$REGION"
echo "Snapshot created: ${SNAPSHOT_ID}"

# Delete the instance
echo "Deleting primary DB instance (simulating region failure) ..."
aws rds delete-db-instance \
  --db-instance-identifier "$DB_IDENTIFIER" \
  --skip-final-snapshot \
  --region "$REGION"

echo "Delete initiated. Waiting for deletion to complete ..."
aws rds wait db-instance-deleted \
  --db-instance-identifier "$DB_IDENTIFIER" \
  --region "$REGION"

echo ""
echo "Primary DB ${DB_IDENTIFIER} DELETED at $(date -u +%Y-%m-%dT%H:%M:%SZ)."
echo "RTO clock starts now. Run dr-restore.sh to recover in ${REGION/us-east-1/eu-west-1}."
