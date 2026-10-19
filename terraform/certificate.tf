# The certificate is currently requested/validated in ACM outside Terraform.
# Consume only a certificate that has finished validation and matches the hostname.
# ACM certificates used by an ALB must be in the same AWS region as the ALB (eu-west-1).
data "aws_acm_certificate" "uptimekuma" {
  domain      = var.domain_name
  statuses    = ["ISSUED"]
  most_recent = true
}
