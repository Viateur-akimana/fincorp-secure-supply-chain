output "ecr_repository_url" {
  description = "ECR repository URL for Docker push"
  value       = module.ecr.repository_url
}

output "codeartifact_npm_endpoint" {
  description = "CodeArtifact npm registry endpoint"
  value       = module.codeartifact.npm_endpoint
}

output "codeartifact_pip_endpoint" {
  description = "CodeArtifact pip index endpoint"
  value       = module.codeartifact.pip_endpoint
}

output "rds_primary_endpoint" {
  description = "Primary RDS instance endpoint"
  value       = module.rds_primary.endpoint
  sensitive   = true
}

output "rds_primary_arn" {
  description = "Primary RDS instance ARN (needed for DR restore)"
  value       = module.rds_primary.db_instance_arn
}

output "backup_vault_arn" {
  description = "Primary backup vault ARN"
  value       = module.backup.primary_vault_arn
}

output "dr_vault_arn" {
  description = "DR backup vault ARN in us-west-2"
  value       = module.backup.dr_vault_arn
}

output "cicd_role_arn" {
  description = "IAM role ARN for GitHub Actions OIDC"
  value       = module.iam.cicd_role_arn
}

output "primary_vpc_id" {
  description = "Primary VPC ID (also in SSM /fincorp/primary/vpc_id)"
  value       = module.networking_primary.vpc_id
}

output "dr_vpc_id" {
  description = "DR VPC ID (also in SSM /fincorp/dr/vpc_id)"
  value       = module.networking_dr.vpc_id
}
