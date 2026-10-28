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

variable "acm_certificate_arn" {
  description = "Full ARN of an already-issued ACM certificate in eu-west-1. Pass it directly so planning and destroying do not depend on a domain-based ACM data-source lookup."
  type        = string

  validation {
    condition     = can(regex(format("^arn:aws:acm:eu-west-1:%s:certificate/.+$", var.aws_account_id), var.acm_certificate_arn))
    error_message = "acm_certificate_arn must be an ACM certificate ARN in eu-west-1 belonging to aws_account_id."
  }
}

variable "domain_name" {
  description = "Fully qualified hostname used for Uptime Kuma HTTPS. The ACM certificate in eu-west-1 must be ISSUED and cover this hostname."
  type        = string
  default     = "uptime.pedromartins9.me"

  validation {
    condition     = length(trimspace(var.domain_name)) > 0 && !contains(split(".", trimspace(var.domain_name)), "")
    error_message = "domain_name must be a non-empty fully qualified DNS hostname without empty labels."
  }
}
