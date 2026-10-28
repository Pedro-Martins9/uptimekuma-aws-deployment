output "uptimekuma_domain_name" {
  description = "Configured DNS hostname for Uptime Kuma."
  value       = var.domain_name
}

output "alb_dns_name" {
  description = "Application Load Balancer DNS name; use as the CNAME target for the hostname in external DNS."
  value       = aws_lb.main.dns_name
}

output "alb_zone_id" {
  description = "Application Load Balancer hosted zone ID, useful for a Route 53 alias record."
  value       = aws_lb.main.zone_id
}

output "acm_certificate_arn" {
  description = "ACM certificate ARN supplied for the configured Uptime Kuma hostname."
  value       = var.acm_certificate_arn
}

output "uptimekuma_url" {
  description = "Public HTTPS URL for the Uptime Kuma dashboard after DNS is configured."
  value       = "https://${var.domain_name}"
}
