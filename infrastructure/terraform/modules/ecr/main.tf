resource "aws_ecr_repository" "this" {
  name                 = var.repository_name
  image_tag_mutability = "IMMUTABLE" # Enforce tag immutability

  image_scanning_configuration {
    scan_on_push = true # Trigger vulnerability scan on every push
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

# Lifecycle policy: keep last 30 tagged images, expire untagged after 1 day
resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after 1 day"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep last 30 tagged releases"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v", "release-"]
          countType     = "imageCountMoreThan"
          countNumber   = 30
        }
        action = { type = "expire" }
      }
    ]
  })
}

# Repository policy: deny pushing the 'latest' tag (enforce semantic versioning)
resource "aws_ecr_repository_policy" "this" {
  repository = aws_ecr_repository.this.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyLatestTag"
        Effect    = "Deny"
        Principal = "*"
        Action    = "ecr:PutImage"
        Condition = {
          StringLike = {
            "ecr:imageTag" = ["latest"]
          }
        }
      }
    ]
  })
}
