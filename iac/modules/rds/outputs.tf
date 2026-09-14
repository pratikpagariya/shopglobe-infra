###############################################################################
# RDS Module — outputs.tf
###############################################################################

output "db_instance_id" {
  value = aws_db_instance.this.id
}

output "db_endpoint" {
  description = "RDS instance connection endpoint"
  value       = aws_db_instance.this.endpoint
}

output "db_host" {
  description = "RDS hostname (without port)"
  value       = aws_db_instance.this.address
}

output "db_port" {
  value = aws_db_instance.this.port
}

output "db_name" {
  value = aws_db_instance.this.db_name
}

output "db_arn" {
  value = aws_db_instance.this.arn
}

output "security_group_id" {
  description = "Security group ID for the RDS instance"
  value       = aws_security_group.rds.id
}

output "db_subnet_group_name" {
  value = aws_db_subnet_group.this.name
}
