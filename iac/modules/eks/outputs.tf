###############################################################################
# EKS Module — outputs.tf
###############################################################################

output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = aws_eks_cluster.this.name
}

output "cluster_arn" {
  description = "ARN of the EKS cluster"
  value       = aws_eks_cluster.this.arn
}

output "cluster_endpoint" {
  description = "Endpoint URL of the EKS cluster API"
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_ca_certificate" {
  description = "Base64-encoded certificate authority data for the cluster"
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_version" {
  description = "Kubernetes version of the cluster"
  value       = aws_eks_cluster.this.version
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster control plane"
  value       = aws_security_group.cluster.id
}

output "node_security_group_id" {
  description = "Security group ID used by EKS managed node groups"
  value       = aws_security_group.node.id
}

output "cluster_role_arn" {
  description = "ARN of the EKS cluster IAM role"
  value       = aws_iam_role.cluster.arn
}

output "node_role_arn" {
  description = "ARN of the EKS node group IAM role"
  value       = aws_iam_role.node.arn
}

output "node_group_names" {
  description = "Map of node group names"
  value       = { for k, ng in aws_eks_node_group.this : k => ng.node_group_name }
}

output "pod_identity_role_arns" {
  description = "Map of Pod Identity IAM role ARNs (key → role ARN)"
  value       = { for k, r in aws_iam_role.pod_identity : k => r.arn }
}

output "addon_names" {
  description = "List of installed EKS addon names"
  value       = [for k, _ in aws_eks_addon.this : k]
}

output "oidc_issuer" {
  description = "OIDC issuer URL (reference only; Pod Identity does not use it)"
  value       = aws_eks_cluster.this.identity[0].oidc[0].issuer
}
