resource "aws_lb" "main" {
  name               = "${local.name}-alb"
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.alb.id]
  subnets            = [for s in aws_subnet.public : s.id]

  # Your app's keep-alive is 75s, deliberately ABOVE this. The reverse causes
  # intermittent 502s when the ALB reuses a connection the app just closed.
  idle_timeout = 60
}

resource "aws_lb_target_group" "app" {
  name     = "${local.name}-app"
  port     = 8000
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  # Points at /readyz, so a failing dependency takes the instance out of
  # rotation. Point it at /healthz and you serve 500s to users instead.
  health_check {
    path                = "/readyz"
    matcher             = "200"
    interval            = 10
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  deregistration_delay = 30
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}
