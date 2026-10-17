variable "aws_account_id" {
  description = "AWS account ID allowed for this deployment. Set via TF_VAR_aws_account_id; do not commit account-specific values."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "aws_account_id must be a 12-digit AWS account ID."
  }
}

variable "budget_alert_email" {
  description = "Email address for account-wide AWS monthly cost budget alerts. Leave empty to disable the budget resource."
  type        = string
  default     = ""
}

variable "monthly_budget_limit_usd" {
  description = "Account-wide monthly cost threshold in USD, measured before promotional credits are applied."
  type        = number
  default     = 10

  validation {
    condition     = var.monthly_budget_limit_usd > 0
    error_message = "monthly_budget_limit_usd must be greater than zero."
  }
}
