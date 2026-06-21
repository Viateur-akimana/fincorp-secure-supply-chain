output "endpoint" {
  value     = aws_db_instance.this.endpoint
  sensitive = true
}

output "db_instance_arn" {
  value = aws_db_instance.this.arn
}

output "db_instance_id" {
  value = aws_db_instance.this.id
}

output "master_user_secret_arn" {
  description = "Secrets Manager ARN holding the RDS master password (auto-rotated)"
  value       = aws_db_instance.this.master_user_secret[0].secret_arn
}
