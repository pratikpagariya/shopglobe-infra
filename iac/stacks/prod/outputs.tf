output "cluster_name" { value = module.eks.cluster_name }
output "cluster_endpoint" { value = module.eks.cluster_endpoint }
output "vpc_id" { value = module.vpc.vpc_id }
output "private_subnets" { value = module.vpc.private_subnet_ids }
output "db_subnet_group" { value = module.vpc.db_subnet_group_name }

output "db_host" { value = module.rds.db_host }
output "db_secret_name" { value = aws_secretsmanager_secret.db.name }
output "payments_queue_urls" { value = { for e, q in module.sqs_payments : e => q.queue_url } }
output "payments_dlq_urls" { value = { for e, q in module.sqs_payments : e => q.dlq_url } }
output "redis_endpoint" { value = module.redis.primary_endpoint }
output "media_buckets" { value = { for e, b in aws_s3_bucket.media : e => b.bucket } }
output "notify_topic_arns" { value = { for e, t in aws_sns_topic.notifications : e => t.arn } }

output "kubeconfig_command" {
  value = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.region}"
}
