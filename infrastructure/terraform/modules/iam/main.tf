# GitHub Actions OIDC provider – allows keyless authentication from GH Actions
resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = ["sts.amazonaws.com"]

  # GitHub's OIDC thumbprint (stable value)
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

# CI/CD IAM Role (assumed by GitHub Actions via OIDC)
resource "aws_iam_role" "cicd" {
  name = "fincorp-cicd-github-actions"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.github.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_org}/${var.github_repo}:*"
        }
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}

# ECR permissions
resource "aws_iam_role_policy" "ecr" {
  role = aws_iam_role.cicd.name
  name = "ecr-push"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage",
          "ecr:DescribeImages",
          "ecr:DescribeImageScanFindings"
        ]
        Resource = var.ecr_repo_arn
      }
    ]
  })
}

# CodeArtifact permissions
# GetAuthorizationToken targets the domain; GetRepositoryEndpoint and
# ReadFromRepository target repository resources — split into two statements.
resource "aws_iam_role_policy" "codeartifact" {
  role = aws_iam_role.cicd.name
  name = "codeartifact-read"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["codeartifact:GetAuthorizationToken"]
        Resource = var.ca_domain_arn
      },
      {
        Effect = "Allow"
        Action = [
          "codeartifact:GetRepositoryEndpoint",
          "codeartifact:ReadFromRepository"
        ]
        Resource = "arn:aws:codeartifact:${var.primary_region}:${var.account_id}:repository/*/*"
      },
      {
        Effect   = "Allow"
        Action   = ["sts:GetServiceBearerToken"]
        Resource = "*"
        Condition = {
          StringEquals = {
            "sts:AWSServiceName" = "codeartifact.amazonaws.com"
          }
        }
      }
    ]
  })
}

# SSM Parameter Store — read /fincorp/* (DR networking, DB identifier)
resource "aws_iam_role_policy" "ssm_read" {
  role = aws_iam_role.cicd.name
  name = "ssm-read-fincorp"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ssm:GetParameter", "ssm:GetParameters"]
      Resource = "arn:aws:ssm:*:${var.account_id}:parameter/fincorp/*"
    }]
  })
}

# RDS — DR drill (simulate failure) and validate restore
resource "aws_iam_role_policy" "rds_dr" {
  role = aws_iam_role.cicd.name
  name = "rds-dr-operations"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "rds:DescribeDBInstances",
        "rds:ModifyDBInstance",
        "rds:DeleteDBInstance",
        "rds:CreateDBSnapshot",
        "rds:DescribeDBSnapshots"
      ]
      Resource = "*"
    }]
  })
}

# AWS Backup — list recovery points and start restore jobs for DR
resource "aws_iam_role_policy" "backup_dr" {
  role = aws_iam_role.cicd.name
  name = "backup-dr-restore"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "backup:ListRecoveryPointsByBackupVault",
          "backup:DescribeRecoveryPoint",
          "backup:StartRestoreJob",
          "backup:DescribeRestoreJob"
        ]
        Resource = "*"
      },
      {
        # dr-restore.sh looks up the backup role ARN dynamically via iam:GetRole
        Effect   = "Allow"
        Action   = ["iam:GetRole"]
        Resource = "arn:aws:iam::${var.account_id}:role/fincorp-aws-backup-role"
      },
      {
        # Pass the backup role to the restore job
        Effect   = "Allow"
        Action   = ["iam:PassRole"]
        Resource = "arn:aws:iam::${var.account_id}:role/fincorp-aws-backup-role"
      }
    ]
  })
}
