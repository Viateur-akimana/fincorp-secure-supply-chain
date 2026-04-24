terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "local" {
    path = "terraform.tfstate"
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

# Secondary provider for DR region
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
  source          = "./modules/iam"
  account_id      = data.aws_caller_identity.current.account_id
  primary_region  = var.primary_region
  ecr_repo_arn    = module.ecr.repository_arn
  ca_domain_arn   = module.codeartifact.domain_arn
}

module "rds_primary" {
  source              = "./modules/rds"
  identifier          = "fincorp-primary"
  region              = var.primary_region
  db_name             = var.db_name
  db_username         = var.db_username
  db_password         = var.db_password
  vpc_id              = var.primary_vpc_id
  subnet_ids          = var.primary_subnet_ids
  allowed_cidr_blocks = var.allowed_cidr_blocks
  multi_az            = false
  backup_retention    = 7
  instance_class      = var.db_instance_class
}

module "backup" {
  source             = "./modules/backup"
  primary_region     = var.primary_region
  dr_region          = var.dr_region
  rds_arn            = module.rds_primary.db_instance_arn
  backup_vault_name  = "fincorp-primary-vault"
  dr_vault_name      = "fincorp-dr-vault"
  account_id         = data.aws_caller_identity.current.account_id

  providers = {
    aws    = aws
    aws.dr = aws.dr
  }
}

# Data sources

data "aws_caller_identity" "current" {}
