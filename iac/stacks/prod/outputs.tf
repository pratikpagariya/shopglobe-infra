output "cluster_name" { value = module.eks.cluster_name }
output "cluster_endpoint" { value = module.eks.cluster_endpoint }
output "vpc_id" { value = module.vpc.vpc_id }
output "private_subnets" { value = module.vpc.private_subnet_ids }
output "db_subnet_group" { value = module.vpc.db_subnet_group_name }

output "db_host" { value = module.rds.db_host }
output "db_secret_name" { value = aws_secretsmanager_secret.db.name }
output "payments_queue_url" { value = module.sqs_payments.queue_url }
output "payments_dlq_url" { value = module.sqs_payments.dlq_url }

output "kubeconfig_command" {
  value = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.region}"
}
