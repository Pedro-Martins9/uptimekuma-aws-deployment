variable "aws_account_id" {
  description = "AWS account ID allowed for this backup-infrastructure deployment. Set via TF_VAR_aws_account_id; do not commit account-specific values."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "aws_account_id must be a 12-digit AWS account ID."
  }
}
