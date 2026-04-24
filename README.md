# FinCorp – Secure Software Supply Chain & Disaster Recovery

This repository implements FinCorp's secure, auditable software supply chain and cross-region disaster recovery plan, satisfying the following objectives:

| Objective | Implementation |
|-----------|---------------|
| Immutable artifact pipeline | GitHub Actions Trivy scan ECR (tag-immutable, scan-on-push) |
| Secure package registry | AWS CodeArtifact proxying public npm and PyPI |
| Build fails on HIGH/CRITICAL CVEs | Trivy `exit-code: 1` + ECR scan gate |
| RDS in us-east-1 | Terraform `modules/rds`, Multi-AZ, encrypted |
| Daily cross-region backups | AWS Backup plan with `cron(0 2 * * ? *)` + copy to eu-west-1 |
| DR failover within 30 minutes | `scripts/dr-restore.sh` with RTO tracking |

---

## Repository Layout

```
.
 app/ # Node.js sample application
 Dockerfile # Multi-stage, non-root, CodeArtifact-aware
 package.json
 src/
 .github/workflows/
 ci-cd.yml # Full secure CI/CD pipeline
 dr-test.yml # DR simulation & recovery workflow
 infrastructure/terraform/
 main.tf # Root module – wires everything together
 variables.tf
 outputs.tf
 modules/
 ecr/ # ECR repo – tag immutability, scan-on-push
 codeartifact/ # CodeArtifact domain + npm/pip repos
 rds/ # RDS PostgreSQL 15, Multi-AZ, encrypted
 backup/ # AWS Backup plan + cross-region copy
 iam/ # GitHub Actions OIDC role
 scripts/
 setup-codeartifact.sh # Configure npm/pip to use CodeArtifact
 check-ecr-vulnerabilities.sh # Gate: fail on HIGH/CRITICAL
 dr-simulate-failure.sh # Delete primary DB (DR drill)
 dr-restore.sh # Restore DB in eu-west-1 within 30 min
 dr-validate.sh # Validate restored DB health
 docs/
 architecture.md # System architecture & design decisions
 pipeline.md # CI/CD pipeline detailed walkthrough
 disaster-recovery.md # DR plan, RTO/RPO, step-by-step recovery
 runbooks/
 dr-failover.md # On-call DR failover runbook
 vulnerability-response.md # CVE response playbook
```

---

## Prerequisites

| Tool | Version |
|------|---------|
| Terraform | ≥ 1.5 |
| AWS CLI | ≥ 2.13 |
| Docker | ≥ 24 |
| Node.js | ≥ 18 |

---

## Quick Start

### 1 – Bootstrap Infrastructure

```bash
cd infrastructure/terraform

# Copy and fill in your values
cp terraform.tfvars.example terraform.tfvars

# Initialise and apply
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

### 2 – Configure GitHub Secrets

| Secret | Description |
|--------|-------------|
| `AWS_CICD_ROLE_ARN` | ARN of the OIDC role (`terraform output cicd_role_arn`) |
| `AWS_ACCOUNT_ID` | 12-digit AWS account ID |
| `DB_USERNAME` | RDS master username |
| `DB_PASSWORD` | RDS master password |
| `PRIMARY_VPC_ID` | VPC ID in us-east-1 |
| `PRIMARY_SUBNET_IDS` | Comma-separated private subnet IDs |
| `PRIMARY_DB_IDENTIFIER` | RDS instance identifier |
| `DR_VPC_ID` | VPC ID in eu-west-1 |
| `DR_SUBNET_GROUP` | DB subnet group name in eu-west-1 |
| `DR_SECURITY_GROUP` | Security group ID in eu-west-1 |
| `DR_KMS_KEY_ARN` | KMS key ARN in eu-west-1 for restored DB |

### 3 – Trigger a Pipeline Run

Push to `main` or open a pull request. The pipeline will:
1. Install deps from CodeArtifact
2. Run unit tests
3. Build the Docker image
4. Run Trivy scan – **fails** if HIGH/CRITICAL CVEs found
5. Push the immutable-tagged image to ECR
6. Wait for ECR's own scan and gate on results
7. Generate an SBOM

### 4 – Run a DR Drill

Go to **Actions DR Simulation & Recovery Test Run workflow**, choose `restore-from-backup`, and type `CONFIRM`.

---

## Security Controls Summary

- **Tag Immutability**: ECR `imageTagMutability = IMMUTABLE` prevents overwriting a released tag.
- **Scan on Push**: Both Trivy (pre-push) and ECR enhanced scanning (post-push) gate on HIGH/CRITICAL.
- **Least-Privilege OIDC**: No long-lived AWS keys; GitHub Actions assumes a scoped role.
- **KMS Encryption**: RDS, backups, CodeArtifact domain all use customer-managed KMS keys with rotation.
- **Vault Lock**: AWS Backup WORM lock prevents backup deletion.
- **SSL Enforced**: `rds.force_ssl = 1` parameter blocks unencrypted connections.
- **Audit Logging**: RDS CloudWatch log exports (postgresql, upgrade) and ECR API CloudTrail.

---

## Compliance Notes

All infrastructure is tagged with `Project`, `Environment`, and `ManagedBy` for cost allocation and compliance reporting. The backup vault lock satisfies SEC 17a-4 WORM requirements for financial records.

---

## Screenshots

### Terraform Infrastructure Apply

![Terraform apply output](screenshoots/image.png)

### AWS CodeArtifact – npm Packages Cached

![CodeArtifact npm repository](screenshoots/image%20copy.png)

### Amazon ECR – Images with Immutable Tags

![ECR image list](screenshoots/image%20copy%202.png)

### ECR Scan – node:18 Image (1 CRITICAL + 11 HIGH Blocked)

![ECR vulnerability scan failure](screenshoots/image%20copy%203.png)

### ECR Scan – node:22 Image (0 Findings – Pipeline Passes)

![ECR vulnerability scan clean](screenshoots/image%20copy%204.png)

### AWS Backup – Primary Vault (us-east-1)

![AWS Backup primary vault](screenshoots/image%20copy%205.png)

### AWS Backup – DR Vault Recovery Point (eu-west-1)

![AWS Backup DR vault](screenshoots/image%20copy%206.png)

### RDS Primary Instance Deleted (Simulated Region Failure)

![Primary RDS deleted](screenshoots/image%20copy%207.png)

### DR Restore – fincorp-dr-restored Available in eu-west-1

![DR restored instance](screenshoots/image%20copy%208.png)

### GitHub Actions – CI/CD Pipeline Run

![GitHub Actions pipeline](screenshoots/image%20copy%209.png)
