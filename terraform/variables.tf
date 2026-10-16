variable "aws_account_id" {
  description = "AWS account ID allowed for this deployment. Set via TF_VAR_aws_account_id or a local tfvars file; do not commit account-specific values."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "aws_account_id must be a 12-digit AWS account ID."
  }
}

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
