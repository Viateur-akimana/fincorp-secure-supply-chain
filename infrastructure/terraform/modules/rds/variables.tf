variable "identifier" {
  type = string
}

variable "region" {
  type = string
}

variable "db_name" {
  type = string
}

variable "db_username" {
  type      = string
  sensitive = true
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "db_subnet_group_name" {
  description = "DB subnet group name (provisioned by the networking module)"
  type        = string
}

variable "security_group_id" {
  description = "RDS security group ID (provisioned by the networking module)"
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key ARN for RDS encryption (provisioned by the networking module)"
  type        = string
}

variable "multi_az" {
  type    = bool
  default = false
}

variable "backup_retention" {
  type    = number
  default = 7
}

variable "instance_class" {
  type    = string
  default = "db.t3.medium"
}
