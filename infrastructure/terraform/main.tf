terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket       = "fincorp-terraform-state-764988411222"
    key          = "artifact-mgmt/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.primary_region
  default_tags {
    tags = {
      Project     = "FinCorp-ArtifactMgmt"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

provider "aws" {
  alias  = "dr"
  region = var.dr_region
  default_tags {
    tags = {
      Project     = "FinCorp-ArtifactMgmt"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Purpose     = "DisasterRecovery"
    }
  }
}

# Modules

module "networking_primary" {
  source      = "./modules/networking"
  name_prefix = "fincorp-primary"
  vpc_cidr    = "10.0.0.0/16"
  region      = var.primary_region
}

module "networking_dr" {
  source      = "./modules/networking"
  name_prefix = "fincorp-dr"
  vpc_cidr    = "10.1.0.0/16"
  region      = var.dr_region

  providers = { aws = aws.dr }
}

module "codeartifact" {
  source      = "./modules/codeartifact"
  domain_name = var.codeartifact_domain
  region      = var.primary_region
  account_id  = data.aws_caller_identity.current.account_id
}

module "ecr" {
  source          = "./modules/ecr"
  repository_name = var.ecr_repository_name
  region          = var.primary_region
}

module "iam" {
  source         = "./modules/iam"
  account_id     = data.aws_caller_identity.current.account_id
  primary_region = var.primary_region
  ecr_repo_arn   = module.ecr.repository_arn
  ca_domain_arn  = module.codeartifact.domain_arn
}

module "rds_primary" {
  source               = "./modules/rds"
  identifier           = "fincorp-primary"
  region               = var.primary_region
  db_name              = var.db_name
  db_username          = var.db_username
  db_subnet_group_name = module.networking_primary.db_subnet_group_name
  security_group_id    = module.networking_primary.rds_security_group_id
  kms_key_arn          = module.networking_primary.rds_kms_key_arn
  multi_az             = true
  backup_retention     = 7
  instance_class       = var.db_instance_class
}

module "backup" {
  source            = "./modules/backup"
  primary_region    = var.primary_region
  dr_region         = var.dr_region
  rds_arn           = module.rds_primary.db_instance_arn
  backup_vault_name = "fincorp-primary-vault"
  dr_vault_name     = "fincorp-dr-vault"
  account_id        = data.aws_caller_identity.current.account_id

  providers = {
    aws    = aws
    aws.dr = aws.dr
  }
}

# SSM Parameter Store — all pipeline and DR networking values auto-populated
# Primary region values
resource "aws_ssm_parameter" "primary_vpc_id" {
  name  = "/fincorp/primary/vpc_id"
  type  = "String"
  value = module.networking_primary.vpc_id
}

resource "aws_ssm_parameter" "primary_subnet_ids" {
  name  = "/fincorp/primary/subnet_ids"
  type  = "String"
  value = jsonencode(module.networking_primary.subnet_ids)
}

resource "aws_ssm_parameter" "primary_db_identifier" {
  name  = "/fincorp/primary/db_identifier"
  type  = "String"
  value = "fincorp-primary"
}

# DR region values — written to primary region SSM (read by GitHub Actions runner)
resource "aws_ssm_parameter" "dr_vpc_id" {
  name  = "/fincorp/dr/vpc_id"
  type  = "String"
  value = module.networking_dr.vpc_id
}

resource "aws_ssm_parameter" "dr_subnet_group" {
  name  = "/fincorp/dr/db_subnet_group"
  type  = "String"
  value = module.networking_dr.db_subnet_group_name
}

resource "aws_ssm_parameter" "dr_security_group_id" {
  name  = "/fincorp/dr/security_group_id"
  type  = "String"
  value = module.networking_dr.rds_security_group_id
}

resource "aws_ssm_parameter" "dr_kms_key_arn" {
  name  = "/fincorp/dr/kms_key_arn"
  type  = "String"
  value = module.networking_dr.rds_kms_key_arn
}

module "cloudtrail" {
  source     = "./modules/cloudtrail"
  account_id = data.aws_caller_identity.current.account_id
  region     = var.primary_region
}

# SSM: store master password secret ARN so apps can fetch credentials without knowing the password
resource "aws_ssm_parameter" "db_secret_arn" {
  name  = "/fincorp/primary/db_secret_arn"
  type  = "String"
  value = module.rds_primary.master_user_secret_arn
}

# Data sources

data "aws_caller_identity" "current" {}
