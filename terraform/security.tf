
resource "aws_security_group" "web" {
  name        = "uptimekuma-web-sg"
  description = "Allow HTTP and HTTPS traffic to Uptime Kuma"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "uptimekuma-web-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "http" {
  security_group_id = aws_security_group.web.id

  description = "HTTP for Caddy and certificate validation"
  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 80
  to_port     = 80
  ip_protocol = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "https" {
  security_group_id = aws_security_group.web.id

  description = "HTTPS web access"
  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 443
  to_port     = 443
  ip_protocol = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "outbound" {
  security_group_id = aws_security_group.web.id

  description = "Outbound connectivity for updates and AWS services"
  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"
}
