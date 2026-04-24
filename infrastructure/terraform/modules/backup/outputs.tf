output "primary_vault_arn" {
  value = aws_backup_vault.primary.arn
}

output "dr_vault_arn" {
  value = aws_backup_vault.dr.arn
}

output "backup_plan_id" {
  value = aws_backup_plan.daily_with_cross_region.id
}

output "backup_role_arn" {
  value = aws_iam_role.backup.arn
}

output "backup_alerts_topic_arn" {
  value = aws_sns_topic.backup_alerts.arn
}
