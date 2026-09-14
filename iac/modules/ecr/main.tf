###############################################################################
# ECR Module — main.tf
###############################################################################

locals {
  name_prefix = "${var.project}-${var.environment}"

  common_tags = merge(var.tags, {
    Module = "ecr"
  })
}

###############################################################################
# ECR Repositories
###############################################################################
resource "aws_ecr_repository" "this" {
  for_each = var.repositories

  name                 = "${local.name_prefix}-${each.key}"
  image_tag_mutability = each.value.image_tag_mutability

  image_scanning_configuration {
    scan_on_push = each.value.scan_on_push
  }

  dynamic "encryption_configuration" {
    for_each = each.value.encryption_type != null ? [1] : []
    content {
      encryption_type = each.value.encryption_type
      kms_key         = each.value.kms_key_arn
    }
  }

  force_delete = each.value.force_delete

  tags = merge(local.common_tags, {
    Name       = "${local.name_prefix}-${each.key}"
    Repository = each.key
  })
}

###############################################################################
# Lifecycle Policies
###############################################################################
resource "aws_ecr_lifecycle_policy" "this" {
  for_each = {
    for k, v in var.repositories : k => v
    if v.lifecycle_policy != null
  }

  repository = aws_ecr_repository.this[each.key].name
  policy     = each.value.lifecycle_policy
}

###############################################################################
# Default lifecycle policy — applied to repos without an explicit one
###############################################################################
locals {
  default_lifecycle_policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last ${var.default_untagged_image_count} untagged images"
        selection = {
          tagStatus   = "untagged"
          countType   = "imageCountMoreThan"
          countNumber = var.default_untagged_image_count
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep last ${var.default_tagged_image_count} tagged images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v", "release-", "sha-"]
          countType     = "imageCountMoreThan"
          countNumber   = var.default_tagged_image_count
        }
        action = { type = "expire" }
      }
    ]
  })
}

resource "aws_ecr_lifecycle_policy" "default" {
  for_each = {
    for k, v in var.repositories : k => v
    if v.lifecycle_policy == null && var.apply_default_lifecycle_policy
  }

  repository = aws_ecr_repository.this[each.key].name
  policy     = local.default_lifecycle_policy
}

###############################################################################
# Repository Policies (cross-account access etc.)
###############################################################################
resource "aws_ecr_repository_policy" "this" {
  for_each = {
    for k, v in var.repositories : k => v
    if v.repository_policy != null
  }

  repository = aws_ecr_repository.this[each.key].name
  policy     = each.value.repository_policy
}
