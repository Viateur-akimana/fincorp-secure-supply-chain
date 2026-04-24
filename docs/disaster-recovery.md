# Disaster Recovery Plan

## Scope

This plan covers the recovery of FinCorp's primary PostgreSQL RDS database from a full **us-east-1 regional failure** to **eu-west-1** within a 30-minute RTO.

---

## RTO / RPO Commitments

| Metric | Target | How achieved |
|--------|--------|-------------|
| Recovery Time Objective (RTO) | ≤ 30 minutes | AWS Backup restore job + scripted automation |
| Recovery Point Objective (RPO) | ≤ 24 hours | Daily backup at 02:00 UTC; weekly at 03:00 UTC Sunday |

To reduce RPO to ~5 minutes, RDS Point-in-Time Recovery (PITR) transaction logs can be used instead of snapshot restore, provided the logs were shipped to eu-west-1 before the failure. This is a future enhancement.

---

## Backup Architecture

### Primary Vault (us-east-1)

- **Vault**: `fincorp-primary-vault`
- **Schedule**: daily `cron(0 2 * * ? *)` and weekly `cron(0 3 ? * SUN *)`
- **Retention**: 35 days (daily), 90 days (weekly)
- **Encryption**: KMS CMK (`alias/backup-primary`)
- **WORM Lock**: min 7 days, max 365 days

### DR Vault (eu-west-1)

- **Vault**: `fincorp-dr-vault`
- **Populated by**: `copy_action` in the AWS Backup plan (copies every backup within the same job)
- **Retention**: 90 days (daily), 365 days (weekly)
- **Encryption**: separate KMS CMK (`alias/backup-dr`) in eu-west-1
- **WORM Lock**: min 7 days, max 365 days

### Timeline of a Nightly Backup

```
02:00 UTC  Backup job starts in us-east-1
 RDS snapshot created in primary vault
 Cross-region copy job starts to eu-west-1

~02:20 UTC Snapshot available in fincorp-dr-vault (eu-west-1)
 Vault lock prevents deletion until day 7
```

---

## Pre-Requisites for Recovery

Before running the restore, ensure the following exist in **eu-west-1**:

| Resource | Purpose |
|----------|---------|
| VPC + private subnets | Network for the restored DB |
| DB Subnet Group | Named subnet group spanning ≥ 2 AZs |
| Security Group | Allow port 5432 from application layer |
| KMS CMK | Encrypt the restored RDS instance |
| IAM Role `fincorp-aws-backup-role` | Must exist in us-east-1 with cross-region trust |

All of these are provisioned by the Terraform `modules/backup` and `modules/rds` modules applied with `provider = aws.dr`.

---

## Recovery Procedure

### Step 1 – Confirm Regional Failure

```bash
# Verify primary DB is unreachable
aws rds describe-db-instances \
  --db-instance-identifier fincorp-primary \
  --region us-east-1
# Expected: error or status != "available"
```

### Step 2 – Identify Latest Recovery Point in DR Vault

```bash
aws backup list-recovery-points-by-backup-vault \
  --backup-vault-name fincorp-dr-vault \
  --region eu-west-1 \
  --by-resource-type RDS \
  --query 'RecoveryPoints | sort_by(@, &CreationDate) | [-1]'
```

Note the `RecoveryPointArn` and `CreationDate`. The `CreationDate` is your effective RPO baseline.

### Step 3 – Execute Restore Script (Automated)

```bash
bash scripts/dr-restore.sh \
  fincorp-dr-vault \          # DR vault name
  eu-west-1 \                 # DR region
  fincorp-dr-restored \       # New DB identifier
  vpc-XXXXXXXX \              # VPC ID in eu-west-1
  fincorp-dr-subnet-group \   # Subnet group name
  sg-XXXXXXXX \               # Security group ID
  arn:aws:kms:eu-west-1:ACCOUNT:key/KEY-ID  # KMS key
```

The script will:
1. Find the most recent recovery point in the DR vault.
2. Submit an `aws backup start-restore-job`.
3. Poll every 30 seconds until the job completes or 30 minutes elapse.
4. Report actual RTO. Exit code 1 if RTO is exceeded.

### Step 4 – Update DNS / Connection String

After restore, update the application's database connection string to point to the restored endpoint:

```bash
# Get the new endpoint
aws rds describe-db-instances \
  --db-instance-identifier fincorp-dr-restored \
  --region eu-west-1 \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text
```

Update the application's Secrets Manager secret or environment variable with the new endpoint.

### Step 5 – Validate

```bash
bash scripts/dr-validate.sh eu-west-1 fincorp-dr-restored
```

Expected output: `Validation PASSED for fincorp-dr-restored in eu-west-1.`

---

## Failback Procedure (After Primary Region Recovers)

1. Re-provision the primary RDS instance via Terraform: `terraform apply`.
2. Dump the DR database and import into the restored primary to bridge the RPO gap.
3. Validate data consistency.
4. Update application connection strings back to us-east-1.
5. Delete the DR instance to stop billing.

---

## Scheduled DR Drills

The `dr-test.yml` workflow runs every **Sunday at 01:00 UTC** in non-destructive validation mode. It:
1. Lists recovery points in the DR vault.
2. Starts a restore job and measures RTO.
3. Validates the restored instance.
4. Deletes the restored instance (cleanup).
5. Uploads a `dr-test-result.json` artifact.

A full destructive drill (simulate-failure restore) should be scheduled **quarterly**, triggered manually via the `simulate-failure` option with `CONFIRM`.

---

## Monitoring & Alerting

| Alert | Trigger | Recipient |
|-------|---------|-----------|
| Backup job failed | `BACKUP_JOB_FAILED` vault notification | SNS on-call |
| Cross-region copy failed | `COPY_JOB_FAILED` vault notification | SNS on-call |
| Restore job failed | `RESTORE_JOB_FAILED` vault notification | SNS on-call |
| RDS unavailable | CloudWatch alarm on `DatabaseConnections` = 0 for 5 min | SNS on-call |

---

## Roles & Responsibilities

| Role | Responsibility during DR |
|------|-------------------------|
| On-call SRE | Execute Steps 1–5, communicate status |
| DB Admin | Validate data integrity after restore |
| Engineering Lead | Approve destructive DR drill execution |
| Security | Verify encryption keys in DR region are valid |
