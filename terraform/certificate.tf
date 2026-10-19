# The certificate is requested/validated in ACM outside Terraform.
# This data-source lookup matches the certificate primary domain name exactly.
# By default it searches var.domain_name. Set acm_certificate_lookup_domain only when
# the certificate primary domain differs; the certificate must still cover var.domain_name.
# The ALB and certificate must both be in eu-west-1.
data "aws_acm_certificate" "uptimekuma" {
  domain      = var.acm_certificate_lookup_domain != null ? var.acm_certificate_lookup_domain : var.domain_name
  statuses    = ["ISSUED"]
  most_recent = true
}
