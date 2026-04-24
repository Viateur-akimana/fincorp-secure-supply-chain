variable "account_id" {
  type = string
}

variable "primary_region" {
  type = string
}

variable "ecr_repo_arn" {
  type = string
}

variable "ca_domain_arn" {
  type = string
}

variable "github_org" {
  description = "GitHub organisation name"
  type        = string
  default     = "Viateur-akimana"
}

variable "github_repo" {
  description = "GitHub repository name"
  type        = string
  default     = "fincorp-secure-supply-chain"
}
