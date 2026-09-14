###############################################################################
# ECR Module — outputs.tf
###############################################################################

output "repository_urls" {
  description = "Map of repository name → URL"
  value       = { for k, r in aws_ecr_repository.this : k => r.repository_url }
}

output "repository_arns" {
  description = "Map of repository name → ARN"
  value       = { for k, r in aws_ecr_repository.this : k => r.arn }
}

output "repository_names" {
  description = "Map of repository key → full repository name"
  value       = { for k, r in aws_ecr_repository.this : k => r.name }
}
