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

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "allowed_cidr_blocks" {
  type    = list(string)
  default = []
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
