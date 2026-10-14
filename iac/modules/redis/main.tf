locals {
  name_prefix = "${var.project}-${var.environment}"
  common_tags = merge(var.tags, { Module = "redis" })
}

resource "aws_elasticache_subnet_group" "this" {
  name       = "${local.name_prefix}-redis"
  subnet_ids = var.subnet_ids
  tags       = local.common_tags
}

resource "aws_security_group" "this" {
  name        = "${local.name_prefix}-redis-sg"
  description = "Redis from EKS nodes and pods"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Redis from attached security groups"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = var.allowed_security_group_ids
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-redis-sg" })
}

# A replication group, not a bare cache cluster, even with one node: it is the
# only resource that can add replicas and fail over later. replicas = 0 daily;
# the full-fidelity weekend flips it to 1 and kills the primary (COST.md).
resource "aws_elasticache_replication_group" "this" {
  replication_group_id = "${local.name_prefix}-redis"
  description          = "${local.name_prefix} cart cache"

  engine         = "redis"
  engine_version = var.engine_version
  node_type      = var.node_type
  port           = 6379

  num_cache_clusters         = 1 + var.replicas
  automatic_failover_enabled = var.replicas > 0
  multi_az_enabled           = var.replicas > 0

  subnet_group_name  = aws_elasticache_subnet_group.this.name
  security_group_ids = [aws_security_group.this.id]

  at_rest_encryption_enabled = true
  # TLS in transit, so clients must use rediss:// (two s's). A plain redis://
  # URL fails as a timeout or reset, not as a message telling you to use TLS.
  transit_encryption_enabled = true

  snapshot_retention_limit = 0 # a cache: losing it means slower, not broken
  apply_immediately        = true

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-redis" })
}
