# CodeArtifact Domain
resource "aws_codeartifact_domain" "this" {
  domain         = var.domain_name
  encryption_key = aws_kms_key.codeartifact.arn
}

resource "aws_kms_key" "codeartifact" {
  description             = "KMS key for CodeArtifact domain ${var.domain_name}"
  deletion_window_in_days = 30
  enable_key_rotation     = true
}

resource "aws_kms_alias" "codeartifact" {
  name          = "alias/codeartifact-${var.domain_name}"
  target_key_id = aws_kms_key.codeartifact.key_id
}

# npm repository (proxied through public npm)
resource "aws_codeartifact_repository" "npm_upstream" {
  repository = "${var.domain_name}-npm-upstream"
  domain     = aws_codeartifact_domain.this.domain

  external_connections {
    external_connection_name = "public:npmjs"
  }
}

resource "aws_codeartifact_repository" "npm" {
  repository = "${var.domain_name}-npm"
  domain     = aws_codeartifact_domain.this.domain
  description = "Internal npm repository with public:npmjs upstream proxy"

  upstream {
    repository_name = aws_codeartifact_repository.npm_upstream.repository
  }
}

# pip repository (proxied through PyPI)
resource "aws_codeartifact_repository" "pip_upstream" {
  repository = "${var.domain_name}-pip-upstream"
  domain     = aws_codeartifact_domain.this.domain

  external_connections {
    external_connection_name = "public:pypi"
  }
}

resource "aws_codeartifact_repository" "pip" {
  repository = "${var.domain_name}-pip"
  domain     = aws_codeartifact_domain.this.domain
  description = "Internal pip repository with PyPI upstream proxy"

  upstream {
    repository_name = aws_codeartifact_repository.pip_upstream.repository
  }
}

# Domain permission policy
resource "aws_codeartifact_domain_permissions_policy" "this" {
  domain          = aws_codeartifact_domain.this.domain
  policy_document = data.aws_iam_policy_document.domain_policy.json
}

data "aws_iam_policy_document" "domain_policy" {
  statement {
    sid    = "AllowAccountAccess"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${var.account_id}:root"]
    }
    actions = [
      "codeartifact:CreateRepository",
      "codeartifact:DescribeDomain",
      "codeartifact:GetAuthorizationToken",
      "codeartifact:GetDomainPermissionsPolicy",
      "codeartifact:ListRepositoriesInDomain",
      "sts:GetServiceBearerToken"
    ]
    resources = ["*"]
  }
}
