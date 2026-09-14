###############################################################################
# VPC Module — outputs.tf
###############################################################################

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value       = [for s in aws_subnet.public : s.id]
}

output "private_subnet_ids" {
  description = "List of private subnet IDs"
  value       = [for s in aws_subnet.private : s.id]
}

output "public_subnet_map" {
  description = "Map of public subnet name → subnet ID"
  value       = { for k, s in aws_subnet.public : k => s.id }
}

output "private_subnet_map" {
  description = "Map of private subnet name → subnet ID"
  value       = { for k, s in aws_subnet.private : k => s.id }
}

output "nat_gateway_ids" {
  description = "Map of NAT gateway IDs"
  value       = { for k, n in aws_nat_gateway.this : k => n.id }
}

output "security_group_ids" {
  description = "Map of security group name → security group ID"
  value       = { for k, sg in aws_security_group.this : k => sg.id }
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway"
  value       = aws_internet_gateway.this.id
}

output "db_subnet_ids" {
  value = [for s in aws_subnet.db : s.id]
}

output "db_subnet_group_name" {
  value = try(aws_db_subnet_group.this[0].name, null)
}

output "vpc_endpoint_sg_id" {
  value = try(aws_security_group.endpoints[0].id, null)
}
