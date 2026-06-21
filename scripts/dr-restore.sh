#!/usr/bin/env bash
# dr-restore.sh
# Restores the RDS database in us-west-2 from the latest AWS Backup recovery point.
# Networking values (VPC, subnet group, SG, KMS key) are read from SSM Parameter Store
# — no manual secrets required.
# Target RTO: 30 minutes.
#
# Usage:
#   dr-restore.sh <dr-vault-name> <dr-region> <new-db-id>
set -euo pipefail

VAULT_NAME="${1:-fincorp-dr-vault}"
DR_REGION="${2:-us-west-2}"
NEW_DB_ID="${3:-fincorp-dr-restored}"
PRIMARY_REGION="${4:-us-east-1}"  # SSM parameters live in the primary region

START_TIME=$(date +%s)
echo "============================================================"
echo "  DR RESTORE: Starting RDS recovery in ${DR_REGION}"
echo "  Target DB  : ${NEW_DB_ID}"
echo "  Vault      : ${VAULT_NAME}"
echo "  Started at : $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "============================================================"

# 1. Read networking config from SSM (provisioned automatically by Terraform)
echo "[1/6] Reading DR networking config from SSM Parameter Store ..."
SUBNET_GROUP=$(aws ssm get-parameter \
  --name "/fincorp/dr/db_subnet_group" \
  --region "$PRIMARY_REGION" \
  --query Parameter.Value --output text)

SECURITY_GROUP=$(aws ssm get-parameter \
  --name "/fincorp/dr/security_group_id" \
  --region "$PRIMARY_REGION" \
  --query Parameter.Value --output text)

KMS_KEY_ARN=$(aws ssm get-parameter \
  --name "/fincorp/dr/kms_key_arn" \
  --region "$PRIMARY_REGION" \
  --query Parameter.Value --output text)

echo "  Subnet group   : ${SUBNET_GROUP}"
echo "  Security group : ${SECURITY_GROUP}"
echo "  KMS key        : ${KMS_KEY_ARN}"

# 2. Find the latest recovery point
echo "[2/6] Locating latest recovery point in DR vault ..."
RECOVERY_POINT_ARN=$(aws backup list-recovery-points-by-backup-vault \
  --backup-vault-name "$VAULT_NAME" \
  --region "$DR_REGION" \
  --by-resource-type "RDS" \
  --query 'RecoveryPoints | sort_by(@, &CreationDate) | [-1].RecoveryPointArn' \
  --output text)

if [[ -z "$RECOVERY_POINT_ARN" || "$RECOVERY_POINT_ARN" == "None" ]]; then
  echo "ERROR: No recovery points found in vault ${VAULT_NAME} in ${DR_REGION}."
  exit 1
fi

CREATION_DATE=$(aws backup describe-recovery-point \
  --backup-vault-name "$VAULT_NAME" \
  --recovery-point-arn "$RECOVERY_POINT_ARN" \
  --region "$DR_REGION" \
  --query 'CreationDate' \
  --output text)

echo "  Recovery point ARN : ${RECOVERY_POINT_ARN}"
echo "  Creation date      : ${CREATION_DATE}"

# 3. Start restore job
echo "[3/6] Starting restore job ..."
RESTORE_JOB_ID=$(aws backup start-restore-job \
  --recovery-point-arn "$RECOVERY_POINT_ARN" \
  --region "$DR_REGION" \
  --iam-role-arn "$(aws iam get-role --role-name fincorp-aws-backup-role --query 'Role.Arn' --output text)" \
  --metadata \
    DBInstanceIdentifier="$NEW_DB_ID" \
    DBSubnetGroupName="$SUBNET_GROUP" \
    VpcSecurityGroupIds="$SECURITY_GROUP" \
    MultiAZ="false" \
    PubliclyAccessible="false" \
    KmsKeyId="$KMS_KEY_ARN" \
    Engine="postgres" \
  --query 'RestoreJobId' \
  --output text)

echo "  Restore job ID: ${RESTORE_JOB_ID}"

# 4. Poll restore job status
echo "[4/6] Waiting for restore job to complete (target: 30 min) ..."
MAX_WAIT=1800
INTERVAL=30
elapsed=0

while true; do
  JOB_STATUS=$(aws backup describe-restore-job \
    --restore-job-id "$RESTORE_JOB_ID" \
    --region "$DR_REGION" \
    --query 'Status' \
    --output text)

  ELAPSED_MIN=$(( ($(date +%s) - START_TIME) / 60 ))
  echo "  [${ELAPSED_MIN}m] Restore job status: ${JOB_STATUS}"

  if [[ "$JOB_STATUS" == "COMPLETED" ]]; then
    break
  fi

  if [[ "$JOB_STATUS" == "FAILED" || "$JOB_STATUS" == "ABORTED" ]]; then
    FAILURE_MSG=$(aws backup describe-restore-job \
      --restore-job-id "$RESTORE_JOB_ID" \
      --region "$DR_REGION" \
      --query 'StatusMessage' --output text)
    echo "ERROR: Restore job ${JOB_STATUS}: ${FAILURE_MSG}"
    exit 1
  fi

  if [[ $elapsed -ge $MAX_WAIT ]]; then
    echo "ERROR: Restore job exceeded 30-minute RTO target."
    exit 1
  fi

  sleep $INTERVAL
  elapsed=$((elapsed + INTERVAL))
done

# 5. Verify the restored instance
echo "[5/6] Verifying restored DB instance ..."
aws rds wait db-instance-available \
  --db-instance-identifier "$NEW_DB_ID" \
  --region "$DR_REGION"

ENDPOINT=$(aws rds describe-db-instances \
  --db-instance-identifier "$NEW_DB_ID" \
  --region "$DR_REGION" \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text)

echo "  DB endpoint: ${ENDPOINT}"

# 6. Report RTO
END_TIME=$(date +%s)
TOTAL_SECONDS=$((END_TIME - START_TIME))
TOTAL_MINUTES=$(( TOTAL_SECONDS / 60 ))
TOTAL_SECS_REMAINDER=$(( TOTAL_SECONDS % 60 ))

echo ""
echo "============================================================"
echo "  DR RESTORE COMPLETE"
echo "  DB identifier : ${NEW_DB_ID}"
echo "  Endpoint      : ${ENDPOINT}"
echo "  Region        : ${DR_REGION}"
echo "  Completed at  : $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "  Total RTO     : ${TOTAL_MINUTES}m ${TOTAL_SECS_REMAINDER}s"
echo "============================================================"

if [[ $TOTAL_MINUTES -le 30 ]]; then
  echo "RTO PASSED: Recovery completed within 30-minute SLA."
else
  echo "RTO EXCEEDED: Recovery took ${TOTAL_MINUTES} minutes (SLA: 30 minutes)."
  exit 1
fi
