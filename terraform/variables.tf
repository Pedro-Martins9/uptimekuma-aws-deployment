variable "alert_email" {
  description = "Optional email recipient for CloudWatch alarm notifications. Confirm the SNS subscription email after deployment."
  type        = string
  default     = null
  nullable    = true
}
