# Architecture Overview

## System Diagram

```
 Developer Workstation / GitHub Actions Runner
 npm install
 Source AWS CodeArtifact
 Code Domain: fincorp
 (Node) npm repo (proxy npmjs)
 pip repo (proxy PyPI)
 docker build
 GitHub Actions Pipeline
 test trivy-scan ecr-push ecr-scan-gate sbom
 push (immutable tag) OIDC AssumeRole
 Amazon ECR IAM Role
 tag-immutable fincorp-cicd-gha
 scan-on-push

         PRIMARY REGION: us-east-1
 RDS PostgreSQL 15 (Multi-AZ)
 fincorp-primary
 Encrypted: KMS CMK
 SSL enforced
 Enhanced monitoring (60s)
 Automated backups (7-day retention)
 AWS Backup
 Plan: daily @ 02:00 UTC + weekly Sunday
 Vault: fincorp-primary-vault (WORM locked)
 Cross-Region Copy
         DR REGION: us-west-2
 AWS Backup
 Vault: fincorp-dr-vault (WORM locked)
 Retention: 90 days daily, 365 days weekly
 Restore job
 RDS PostgreSQL 15 (restored)
 fincorp-dr-restored
 RTO target: ≤ 30 minutes
```

---

## Design Decisions

### 1. Tag Immutability in ECR

ECR's `imageTagMutability = IMMUTABLE` prevents any subsequent `docker push` from overwriting an existing tag. This guarantees that once an image is tagged `v42-abc12345`, it can never be replaced by a different image with the same tag, providing a reliable audit trail and preventing "tag hijacking" attacks in the supply chain.

A repository policy layer additionally denies pushing to the `latest` tag, which has no semantic version and is a common vector for accidental overwrites.

### 2. Dual-Layer Vulnerability Scanning

The pipeline uses two independent scanners:
- **Trivy** (pre-push, in the CI runner): scans the locally built image against the NVD/GitHub Advisory databases. The `exit-code: 1` flag causes a hard build failure if CRITICAL or HIGH findings exist.
- **ECR Enhanced Scanning** (post-push, managed by AWS): uses Amazon Inspector under the hood, with its own CVE database. The `check-ecr-vulnerabilities.sh` script gates the pipeline on these results as well.

This defence-in-depth approach catches vulnerabilities that may appear in one database but not the other.

### 3. CodeArtifact as Package Proxy

Routing all npm and pip installs through CodeArtifact provides:
- **Auditability**: every package pull is logged in CloudTrail.
- **Caching**: packages are cached in the region, reducing latency and external dependency.
- **Allowlisting capability**: administrators can block specific packages by removing them from the upstream connection and adding deny policies.
- **Token expiry**: CodeArtifact tokens expire (15 minutes in CI), reducing blast radius if a token leaks.

### 4. AWS Backup with Vault Lock (WORM)

The `aws_backup_vault_lock_configuration` resource enables a Write-Once-Read-Many lock on both vaults. After the lock is applied:
- No backup can be deleted before its minimum retention period (7 days).
- No backup is kept beyond the maximum retention period.
- The lock itself cannot be removed (compliance mode).

This satisfies financial-services requirements (e.g., SEC 17a-4, FINRA) for immutable audit records.

### 5. GitHub Actions OIDC (Keyless Auth)

No long-lived AWS access keys are stored in GitHub Secrets. Instead, GitHub's OIDC provider issues short-lived JWT tokens, and the IAM role's trust policy validates the `sub` claim (repo + branch). This eliminates key rotation concerns and reduces secret-sprawl risk.

### 6. Multi-AZ RDS

The primary RDS instance runs Multi-AZ so that an Availability Zone failure within us-east-1 causes an automatic failover (typically < 60 seconds) without involving the DR process. The DR plan activates only for a full regional failure.

---

## RPO and RTO Targets

| Scenario | RTO | RPO |
|----------|-----|-----|
| AZ failure (primary region) | < 1 min (Multi-AZ auto-failover) | 0 (synchronous standby) |
| Region failure | ≤ 30 min | ≤ 24 h (daily backup cadence) |

To reduce RPO further, consider enabling RDS automated backups with a 5-minute transaction log backup frequency and restoring to a point-in-time rather than a daily snapshot.
