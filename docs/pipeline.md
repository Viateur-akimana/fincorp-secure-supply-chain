# CI/CD Pipeline – Detailed Walkthrough

## Overview

The pipeline is defined in [.github/workflows/ci-cd.yml](../.github/workflows/ci-cd.yml) and consists of five jobs:

```
push to main / pull request
 secret-scan (Gitleaks – gates ALL downstream jobs)
 |
 test build-and-scan sbom
 (lint + (Docker build, (SPDX JSON
 jest) Trivy, ECR push, via Syft)
 ECR scan gate,
 Cosign sign)
                     on pull_request only
 terraform-plan
 (validate + plan)
```

---

## Job: `secret-scan`

Runs **before every other job** on both `push` and `pull_request` events. Uses Gitleaks to scan
the full git history for committed secrets (API keys, passwords, tokens). All downstream jobs
declare `needs: secret-scan` so a leak detection causes an immediate pipeline halt before any
AWS credentials are requested.

---

## Job: `test`

### Steps

1. **Checkout** – fetches source code.
2. **AWS OIDC login** – assumes `fincorp-cicd-github-actions` role.
3. **Get CodeArtifact token** – calls `aws codeartifact get-authorization-token`. The token is masked in logs.
4. **Configure npm** – sets the npm registry to the CodeArtifact endpoint using the masked token.
5. **`npm ci`** – installs exact lockfile versions from CodeArtifact (not directly from npmjs).
6. **Lint** – ESLint; currently non-blocking (`|| true`) to allow gradual adoption.
7. **Jest tests + coverage** – test failure here blocks all downstream jobs.

---

## Job: `build-and-scan`

### Steps

1. **Build Docker image** – multi-stage build with:
   - `NPM_REGISTRY` build-arg pointing to CodeArtifact (packages never touch public npmjs during build).
   - `APP_VERSION` build-arg injected as an environment variable in the final image.
   - Non-root user (`appuser`) in the production stage.

2. **Trivy scan** (BEFORE push):
   - Scans the local image against CRITICAL and HIGH severity only.
   - Output: SARIF file uploaded to GitHub Security tab.
   - **`exit-code: 1`**: build fails immediately if any CRITICAL or HIGH finding is present.
   - `ignore-unfixed: false`: even vulnerabilities with no upstream fix fail the build (they must be acknowledged or the base image updated).

3. **Push to ECR** – only reached if Trivy passes. The tag format is `v<run_number>-<sha_short>` (e.g., `v42-abc12345`). ECR's `IMMUTABLE` setting rejects any attempt to overwrite this tag.

4. **ECR scan gate** – waits up to 120 seconds for ECR's own scan, then runs `check-ecr-vulnerabilities.sh` which parses `findingSeverityCounts` and exits non-zero if CRITICAL or HIGH counts > 0.

5. **Image metadata artifact** – saves `image_uri` and `image_digest` as a JSON artifact for deployment jobs to consume.

---

## Job: `sbom`

Generates a Software Bill of Materials in SPDX JSON format using Syft. The SBOM is uploaded as a workflow artifact for compliance/audit purposes. It captures every OS package and Node.js module present in the final image layer.

---

## Job: `terraform-plan`

Runs on pull requests only. Performs `terraform init`, `validate`, and `plan` against the infrastructure modules. The plan output is uploaded as an artifact so reviewers can inspect changes before merge.

---

## Failure Modes

| Failure | Outcome |
|---------|---------|
| Gitleaks finds a secret | Pipeline halts immediately; no AWS jobs run |
| Unit tests fail | Pipeline stops at `test`; no image built |
| Trivy finds HIGH/CRITICAL | Pipeline stops at `build-and-scan` before push |
| ECR tag already exists (immutable) | Push rejected by ECR; pipeline fails |
| ECR scan finds HIGH/CRITICAL | Pipeline fails after push; image is quarantined in ECR |

---

## Image Tagging Convention

| Tag format | Meaning |
|-----------|---------|
| `v<N>-<sha8>` | Immutable release tag (e.g., `v42-abc12345`) |
| `build-<N>` | Secondary tag for easy human lookup by run number |

The `latest` tag is explicitly denied by the ECR repository policy.

---

## Security of the Pipeline Itself

- **Pinned action versions**: all `uses:` lines are pinned to immutable commit SHAs (e.g. `actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683`), not mutable version tags. This prevents supply chain attacks where a tag is silently moved to malicious code.
- **Minimal permissions**: the workflow declares `permissions: id-token: write, contents: read`.
- **No long-lived secrets**: AWS credentials are obtained via OIDC; the CodeArtifact token is masked and scoped to 15 minutes.
- **SARIF upload**: vulnerability reports go to GitHub's Security tab for traceability, independent of whether the build passed or failed.
