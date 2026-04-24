output "domain_arn" {
  value = aws_codeartifact_domain.this.arn
}

output "npm_endpoint" {
  value = "https://${aws_codeartifact_domain.this.domain}-${var.account_id}.d.codeartifact.${var.region}.amazonaws.com/npm/${aws_codeartifact_repository.npm.repository}/"
}

output "pip_endpoint" {
  value = "https://${aws_codeartifact_domain.this.domain}-${var.account_id}.d.codeartifact.${var.region}.amazonaws.com/pypi/${aws_codeartifact_repository.pip.repository}/simple/"
}

output "npm_repository_name" {
  value = aws_codeartifact_repository.npm.repository
}

output "pip_repository_name" {
  value = aws_codeartifact_repository.pip.repository
}
