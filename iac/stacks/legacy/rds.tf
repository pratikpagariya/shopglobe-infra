resource "aws_db_subnet_group" "pg" {
  name       = "${local.name}-pg"
  subnet_ids = [for s in aws_subnet.db : s.id]
}

resource "aws_db_parameter_group" "pg" {
  name   = "${local.name}-pg16"
  family = "postgres16"

  # Deliberately low. Day 4 you scale pods until you exhaust this.
  parameter {
    name         = "max_connections"
    value        = "100"
    apply_method = "pending-reboot"
  }

  # Log anything over 200ms. This is how you FIND the N+1 query.
  parameter {
    name  = "log_min_duration_statement"
    value = "200"
  }
}

resource "aws_db_instance" "pg" {
  identifier     = "${local.name}-pg"
  engine         = "postgres"
  engine_version = "16"
  instance_class = var.db_instance_class

  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = "shopglobe"
  username = "shop"

  # AWS generates the password into Secrets Manager. Terraform never sees it,
  # so it never lands in state. This is the answer to "your state file
  # contains the DB password".
  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.pg.name
  vpc_security_group_ids = [aws_security_group.db.id]
  parameter_group_name   = aws_db_parameter_group.pg.name

  multi_az                = false
  publicly_accessible     = false
  backup_retention_period = 1

  # Legacy stack is destroyed after day 2. The prod stack sets both true.
  skip_final_snapshot = true
  deletion_protection = false
  apply_immediately   = true
}
