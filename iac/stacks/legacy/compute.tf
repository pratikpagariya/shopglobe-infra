resource "aws_launch_template" "app" {
  name_prefix   = "${local.name}-app-"
  image_id      = data.aws_ssm_parameter.ubuntu.value
  instance_type = var.app_instance_type

  iam_instance_profile {
    name = aws_iam_instance_profile.app.name
  }

  vpc_security_group_ids = [aws_security_group.app.id]

  user_data = base64encode(templatefile("${path.module}/templates/user_data_app.sh", {
    artifact_bucket = var.artifact_bucket
    db_host         = aws_db_instance.pg.address
    db_secret_arn   = aws_db_instance.pg.master_user_secret[0].secret_arn
    region          = var.region
  }))

  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      volume_size = 20
      volume_type = "gp3" # never gp2: gp3 is cheaper and faster
      encrypted   = true
    }
  }

  metadata_options {
    http_tokens = "required" # IMDSv2 only. IMDSv1 is an SSRF credential-theft path.
  }

  # credit_specification is only valid on burstable (t*) types, so emit it
  # conditionally. This is what dynamic blocks are for.
  dynamic "credit_specification" {
    for_each = startswith(var.app_instance_type, "t3.") ? [1] : []
    content {
      cpu_credits = var.cpu_credits
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "${local.name}-app", Role = "app" }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "app" {
  name                = "${local.name}-app"
  min_size            = var.asg_min
  max_size            = var.asg_max
  desired_capacity    = var.asg_min
  vpc_zone_identifier = [for s in aws_subnet.private : s.id]
  target_group_arns   = [aws_lb_target_group.app.arn]

  # ELB not EC2: "EC2" only checks the instance is running, "ELB" checks your
  # app actually answers /readyz and replaces it if not.
  health_check_type         = "ELB"
  health_check_grace_period = 180

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
  }

  tag {
    key                 = "Name"
    value               = "${local.name}-app"
    propagate_at_launch = true
  }
  tag {
    key                 = "Role"
    value               = "app"
    propagate_at_launch = true
  }
  tag {
    key                 = "Env"
    value               = "legacy"
    propagate_at_launch = true
  }
}

resource "aws_instance" "mon" {
  ami                    = data.aws_ssm_parameter.ubuntu.value
  instance_type          = var.mon_instance_type
  subnet_id              = aws_subnet.public[local.azs[0]].id
  vpc_security_group_ids = [aws_security_group.mon.id]
  iam_instance_profile   = aws_iam_instance_profile.mon.name
  user_data              = base64encode(file("${path.module}/templates/user_data_mon.sh"))

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
    encrypted   = true
  }

  metadata_options {
    http_tokens = "required"
  }

  dynamic "credit_specification" {
    for_each = startswith(var.mon_instance_type, "t3.") ? [1] : []
    content {
      cpu_credits = var.cpu_credits
    }
  }

  tags = { Name = "${local.name}-mon", Role = "monitoring" }
}
