# Public entry point: the Application Load Balancer.
# Public IPv4 web traffic is allowed only on ports 80 and 443; ECS host ports are not public.
resource "aws_security_group" "alb" {
  name        = "uptimekuma-alb-sg"
  description = "Allow public IPv4 HTTP-to-HTTPS redirect and HTTPS access to the ALB"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "uptimekuma-alb-sg"
  }
}

# ECS container instances. No public inbound access is allowed.
resource "aws_security_group" "ecs_instances" {
  name        = "uptimekuma-ecs-instances-sg"
  description = "Control traffic to ECS container instances"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "uptimekuma-ecs-instances-sg"
  }
}

# HTTP is only needed to redirect clients to HTTPS.
resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  description       = "Public IPv4 HTTP traffic; listener redirects to HTTPS"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id
  description       = "Public IPv4 HTTPS traffic to the ALB"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

# The ALB can forward traffic to dynamically assigned ECS host ports.
resource "aws_vpc_security_group_egress_rule" "alb_to_ecs" {
  security_group_id            = aws_security_group.alb.id
  description                  = "Forward traffic to ECS dynamic host ports"
  referenced_security_group_id = aws_security_group.ecs_instances.id
  from_port                    = 32768
  to_port                      = 65535
  ip_protocol                  = "tcp"
}

# ECS instances accept application traffic only from the ALB.
resource "aws_vpc_security_group_ingress_rule" "ecs_from_alb" {
  security_group_id            = aws_security_group.ecs_instances.id
  description                  = "ALB traffic to ECS dynamic host ports"
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = 32768
  to_port                      = 65535
  ip_protocol                  = "tcp"
}

# ECS instances need HTTP egress for monitored websites.
resource "aws_vpc_security_group_egress_rule" "ecs_http" {
  security_group_id = aws_security_group.ecs_instances.id
  description       = "HTTP for monitored websites"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

# HTTPS is needed for container image pulls and AWS service APIs,
# as well as HTTPS monitoring checks.
resource "aws_vpc_security_group_egress_rule" "ecs_https" {
  security_group_id = aws_security_group.ecs_instances.id
  description       = "HTTPS for AWS APIs, image pulls, and monitoring"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}
