# The certificate is requested/validated in ACM outside Terraform.
# This data-source lookup matches the certificate primary domain name exactly; by default,
# request the certificate for uptime.pedromartins9.me as the primary domain.
# Ensure the issued certificate covers var.domain_name and is in the ALB region (eu-west-1).
data "aws_acm_certificate" "uptimekuma" {
  domain      = var.domain_name
  statuses    = ["ISSUED"]
  most_recent = true
}
