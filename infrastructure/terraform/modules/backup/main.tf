terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 5.0"
      configuration_aliases = [aws, aws.dr]
    }
  }
}

# Primary Backup Vault (us-east-1)
resource "aws_kms_key" "backup_primary" {
  provider                = aws
  description             = "KMS key for primary AWS Backup vault"
  deletion_window_in_days = 30
  enable_key_rotation     = true
}

resource "aws_backup_vault" "primary" {
  provider    = aws
  name        = var.backup_vault_name
  kms_key_arn = aws_kms_key.backup_primary.arn
}

# DR Backup Vault (eu-west-1)
resource "aws_kms_key" "backup_dr" {
  provider                = aws.dr
  description             = "KMS key for DR AWS Backup vault"
  deletion_window_in_days = 30
  enable_key_rotation     = true
}

resource "aws_backup_vault" "dr" {
  provider    = aws.dr
  name        = var.dr_vault_name
  kms_key_arn = aws_kms_key.backup_dr.arn
}

# IAM Role for AWS Backup
resource "aws_iam_role" "backup" {
  provider = aws
  name     = "fincorp-aws-backup-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "backup.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "backup_policy" {
  provider   = aws
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

resource "aws_iam_role_policy_attachment" "restore_policy" {
  provider   = aws
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores"
}

# Allow cross-region copy
resource "aws_iam_role_policy" "backup_cross_region" {
  provider = aws
  role     = aws_iam_role.backup.name
  name     = "cross-region-copy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["backup:CopyIntoBackupVault"]
        Resource = aws_backup_vault.dr.arn
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:GenerateDataKey"]
        Resource = [
          aws_kms_key.backup_primary.arn,
          aws_kms_key.backup_dr.arn
        ]
      }
    ]
  })
}

# Backup Plan
resource "aws_backup_plan" "daily_with_cross_region" {
  provider = aws
  name     = "fincorp-daily-cross-region"

  rule {
    rule_name         = "daily-backup"
    target_vault_name = aws_backup_vault.primary.name
    schedule          = "cron(0 2 * * ? *)" # 02:00 UTC daily

    lifecycle {
      delete_after = 35 # Keep 35 days in primary vault
    }

    copy_action {
      destination_vault_arn = aws_backup_vault.dr.arn

      lifecycle {
        delete_after = 90 # Keep 90 days in DR vault
      }
    }

    recovery_point_tags = {
      BackupType = "Scheduled"
      Region     = var.primary_region
      DrTarget   = var.dr_region
    }
  }

  # Weekly full backup on Sundays with longer retention
  rule {
    rule_name         = "weekly-backup"
    target_vault_name = aws_backup_vault.primary.name
    schedule          = "cron(0 3 ? * SUN *)"

    lifecycle {
      delete_after = 90
    }

    copy_action {
      destination_vault_arn = aws_backup_vault.dr.arn

      lifecycle {
        delete_after = 365 # Keep weekly backups 1 year in DR
      }
    }

    recovery_point_tags = {
      BackupType = "Weekly"
      Region     = var.primary_region
      DrTarget   = var.dr_region
    }
  }
}

# Backup Selection (tag-based)
resource "aws_backup_selection" "rds" {
  provider     = aws
  iam_role_arn = aws_iam_role.backup.arn
  name         = "fincorp-rds-selection"
  plan_id      = aws_backup_plan.daily_with_cross_region.id

  resources = [var.rds_arn]
}

# Vault Lock (WORM – prevents backup deletion)
resource "aws_backup_vault_lock_configuration" "primary" {
  provider          = aws
  backup_vault_name = aws_backup_vault.primary.name
  min_retention_days = 7
  max_retention_days = 365
}

resource "aws_backup_vault_lock_configuration" "dr" {
  provider          = aws.dr
  backup_vault_name = aws_backup_vault.dr.name
  min_retention_days = 7
  max_retention_days = 365
}

# SNS Alerts for backup failures
resource "aws_sns_topic" "backup_alerts" {
  provider = aws
  name     = "fincorp-backup-alerts"
}

resource "aws_backup_vault_notifications" "primary" {
  provider            = aws
  backup_vault_name   = aws_backup_vault.primary.name
  sns_topic_arn       = aws_sns_topic.backup_alerts.arn
  backup_vault_events = ["BACKUP_JOB_FAILED", "COPY_JOB_FAILED", "RESTORE_JOB_FAILED"]
}
