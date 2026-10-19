resource "aws_lb" "main" {
  name               = "uptimekuma-alb"
  internal           = false
  load_balancer_type = "application"

  security_groups = [
    aws_security_group.alb.id
  ]

  subnets = [
    aws_subnet.public.id,
    aws_subnet.public_secondary.id
  ]

  tags = {
    Name = "uptimekuma-alb"
  }
}

resource "aws_lb_target_group" "uptimekuma" {
  name        = "uptimekuma-tg"
  port        = 3001
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = aws_vpc.main.id

  health_check {
    enabled             = true
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200-399"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = {
    Name = "uptimekuma-target-group"
  }
}

# Redirect all HTTP requests to the TLS listener.
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# TLS terminates at the ALB. The internal target-group traffic stays HTTP.
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = data.aws_acm_certificate.uptimekuma.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.uptimekuma.arn
  }
}
