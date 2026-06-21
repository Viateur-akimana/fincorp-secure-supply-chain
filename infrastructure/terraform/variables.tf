variable "primary_region" {
  description = "AWS primary region"
  type        = string
  default     = "us-east-1"
}

variable "dr_region" {
  description = "AWS disaster-recovery region"
  type        = string
  default     = "us-west-2"
}

variable "environment" {
  description = "Deployment environment (prod, staging)"
  type        = string
  default     = "prod"
}

variable "codeartifact_domain" {
  description = "CodeArtifact domain name"
  type        = string
  default     = "fincorp"
}

variable "ecr_repository_name" {
  description = "ECR repository name"
  type        = string
  default     = "fincorp/artifact-service"
}

variable "db_name" {
  description = "RDS database name"
  type        = string
  default     = "fincorp_db"
}

variable "db_username" {
  description = "RDS master username"
  type        = string
  sensitive   = true
}

variable "db_password" {
  description = "RDS master password"
  type        = string
  sensitive   = true
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.medium"
}
