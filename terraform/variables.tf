variable "alert_email" {
  description = "Optional email recipient for CloudWatch alarm notifications. Confirm the SNS subscription email after deployment."
  type        = string
  default     = null
  nullable    = true
}

variable "allowed_client_ipv4_cidr" {
  description = "Trusted client public IPv4 CIDR allowed to access the temporary HTTP ALB endpoint. Use a single address in /32 notation."
  type        = string

  validation {
    condition     = can(cidrnetmask(var.allowed_client_ipv4_cidr)) && endswith(var.allowed_client_ipv4_cidr, "/32")
    error_message = "allowed_client_ipv4_cidr must be one public IPv4 address in /32 CIDR notation, for example the output of curl -4 https://checkip.amazonaws.com followed by /32."
  }
}
