provider "aws" {
  region = "eu-west-1"

  # Fail closed if credentials point at the wrong AWS account.
  allowed_account_ids = [var.aws_account_id]

  default_tags {
    tags = {
      Project   = "uptimekuma"
      ManagedBy = "Terraform"
      Purpose   = "Persistent cost notifications"
    }
  }
}
