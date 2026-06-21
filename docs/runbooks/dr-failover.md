# Runbook: DR Failover to us-west-2

**Severity**: P1 – Production outage  
**Target RTO**: 30 minutes from decision to restore complete  
**Last tested**: See `dr-test-result.json` artifacts in GitHub Actions

---

## Decision Tree

```
Alert fires: us-east-1 RDS unreachable
Is it an AZ failure only?
 YES Multi-AZ auto-failover in progress – wait 60s, re-check
 NO Confirm regional scope (AWS Service Health Dashboard)
        Declare DR event. Start 30-min RTO clock.
        Execute Steps 1–5 below
```

---

## Checklist

### T+0 — Declare DR Event

- [ ] Confirm AWS Service Health Dashboard shows us-east-1 incident.
- [ ] Notify stakeholders: Engineering Lead, DB Admin, Security.
- [ ] Open incident ticket. Start RTO stopwatch.

### T+2 — Verify DR Vault Has Recent Recovery Point

```bash
export DR_REGION=us-west-2
export DR_VAULT=fincorp-dr-vault

aws backup list-recovery-points-by-backup-vault \
  --backup-vault-name "$DR_VAULT" \
  --region "$DR_REGION" \
  --by-resource-type RDS \
  --query 'RecoveryPoints | sort_by(@, &CreationDate) | [-1].{Arn:RecoveryPointArn, Created:CreationDate}' \
  --output table
```

- [ ] Confirm a recovery point exists and note its `CreationDate` (= RPO).

### T+5 — Run Restore Script

Networking values (VPC, subnet group, security group, KMS key) are read automatically
from SSM Parameter Store — no manual values needed.

```bash
bash scripts/dr-restore.sh \
  "fincorp-dr-vault" \
  "us-west-2" \
  "fincorp-dr-restored-$(date +%Y%m%d)"
```

- [ ] Script exits 0 within 30 minutes.
- [ ] Note actual elapsed time in incident ticket.

### T+25 (target) — Validate Restore

```bash
bash scripts/dr-validate.sh "$DR_REGION" "fincorp-dr-restored-$(date +%Y%m%d)"
```

- [ ] Output ends with `Validation PASSED`.

### T+28 — Update Application Configuration

```bash
# Get new endpoint
ENDPOINT=$(aws rds describe-db-instances \
  --db-instance-identifier "fincorp-dr-restored-$(date +%Y%m%d)" \
  --region "$DR_REGION" \
  --query 'DBInstances[0].Endpoint.Address' --output text)
echo "New DB endpoint: $ENDPOINT"

# Update Secrets Manager (adjust secret name as needed)
aws secretsmanager update-secret \
  --secret-id fincorp/db/endpoint \
  --secret-string "{\"host\":\"$ENDPOINT\",\"port\":5432}" \
  --region "$DR_REGION"
```

- [ ] Redeploy application pods/tasks to pick up new endpoint.
- [ ] Smoke test critical application flows.

### T+30 — Confirm Recovery

- [ ] Application health check returns `200 OK`.
- [ ] Database metrics visible in CloudWatch (us-west-2).
- [ ] Close RTO stopwatch. Record actual RTO in incident ticket.

---

## Escalation

| Condition | Escalation |
|-----------|-----------|
| Restore job FAILED | Engage AWS Support (Production support required) |
| RTO > 30 min | Notify CTO, update SLA breach log |
| Vault has no recovery points | Engage AWS Backup support; use final RDS snapshot as fallback |

---

## Post-Incident

Within 48 hours of DR event:
1. Write post-mortem documenting timeline and RTO achieved.
2. Check if any backup jobs failed in the days preceding the incident.
3. Review RPO gap between last recovery point and incident time.
4. Update this runbook if any steps were inaccurate.
