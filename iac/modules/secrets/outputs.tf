###############################################################################
# Secrets Manager Module — outputs.tf
###############################################################################

output "secret_arns" {
  description = "Map of secret key → ARN"
  value       = { for k, s in aws_secretsmanager_secret.this : k => s.arn }
}

output "secret_names" {
  description = "Map of secret key → full secret name"
  value       = { for k, s in aws_secretsmanager_secret.this : k => s.name }
}

output "secret_arn_prefix" {
  description = "ARN prefix covering all secrets created by this module (for IAM scoping)"
  value       = "arn:aws:secretsmanager:*:*:secret:${var.project}-${var.environment}-*"
}
