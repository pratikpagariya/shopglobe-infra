###############################################################################
# RDS Module — main.tf
###############################################################################

locals {
  name_prefix = "${var.project}-${var.environment}"

  common_tags = merge(var.tags, {
    Module = "rds"
  })
}

###############################################################################
# DB Subnet Group
###############################################################################
resource "aws_db_subnet_group" "this" {
  name        = "${local.name_prefix}-${var.identifier}-subnet-grp"
  description = "Subnet group for ${var.identifier} RDS instance"
  subnet_ids  = var.subnet_ids

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-${var.identifier}-subnet-grp"
  })
}

###############################################################################
# DB Parameter Group
###############################################################################
resource "aws_db_parameter_group" "this" {
  name        = "${local.name_prefix}-${var.identifier}-pg"
  family      = var.parameter_group_family
  description = "Parameter group for ${var.identifier}"

  dynamic "parameter" {
    for_each = var.db_parameters
    content {
      name         = parameter.value.name
      value        = parameter.value.value
      apply_method = lookup(parameter.value, "apply_method", "immediate")
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-${var.identifier}-pg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

###############################################################################
# Security Group
###############################################################################
resource "aws_security_group" "rds" {
  name        = "${local.name_prefix}-${var.identifier}-sg"
  description = "Security group for RDS ${var.identifier}"
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = length(var.allowed_security_group_ids) > 0 ? [1] : []
    content {
      description     = "Allow DB access from attached security groups"
      from_port       = var.db_port
      to_port         = var.db_port
      protocol        = "tcp"
      security_groups = var.allowed_security_group_ids
    }
  }

  dynamic "ingress" {
    for_each = length(var.allowed_cidr_blocks) > 0 ? [1] : []
    content {
      description = "Allow from specified CIDR blocks"
      from_port   = var.db_port
      to_port     = var.db_port
      protocol    = "tcp"
      cidr_blocks = var.allowed_cidr_blocks
    }
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-${var.identifier}-sg"
  })
}

###############################################################################
# RDS Instance
###############################################################################
resource "aws_db_instance" "this" {
  identifier = "${local.name_prefix}-${var.identifier}"

  # Engine
  engine               = var.engine
  engine_version       = var.engine_version
  instance_class       = var.instance_class
  parameter_group_name = aws_db_parameter_group.this.name
  option_group_name    = var.option_group_name

  # Storage
  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = var.storage_type
  storage_encrypted     = var.storage_encrypted
  kms_key_id            = var.kms_key_arn

  # Database
  db_name  = var.db_name
  username = var.db_username
  password = var.db_password
  port     = var.db_port

  # Network
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false

  # High Availability
  multi_az = var.multi_az

  # Backups
  backup_retention_period   = var.backup_retention_period
  backup_window             = var.backup_window
  maintenance_window        = var.maintenance_window
  copy_tags_to_snapshot     = true
  delete_automated_backups  = var.delete_automated_backups
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${local.name_prefix}-${var.identifier}-final"
  skip_final_snapshot       = var.skip_final_snapshot

  # Monitoring
  monitoring_interval = var.monitoring_interval
  monitoring_role_arn = var.monitoring_interval > 0 ? aws_iam_role.rds_enhanced_monitoring[0].arn : null

  enabled_cloudwatch_logs_exports = var.cloudwatch_logs_exports

  # Updates
  auto_minor_version_upgrade  = var.auto_minor_version_upgrade
  allow_major_version_upgrade = false
  apply_immediately           = var.apply_immediately
  deletion_protection         = var.deletion_protection

  performance_insights_enabled          = var.performance_insights_enabled
  performance_insights_retention_period = var.performance_insights_enabled ? var.performance_insights_retention_period : null

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-${var.identifier}"
  })

  lifecycle {
    ignore_changes = [password]
  }
}

###############################################################################
# Enhanced Monitoring Role (conditional)
###############################################################################
resource "aws_iam_role" "rds_enhanced_monitoring" {
  count = var.monitoring_interval > 0 ? 1 : 0

  name = "${local.name_prefix}-${var.identifier}-rds-monitoring"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "monitoring.rds.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-${var.identifier}-rds-monitoring"
  })
}

resource "aws_iam_role_policy_attachment" "rds_enhanced_monitoring" {
  count = var.monitoring_interval > 0 ? 1 : 0

  role       = aws_iam_role.rds_enhanced_monitoring[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}
