provider "aws" {
  region = "eu-west-1"

  allowed_account_ids = [var.aws_account_id]

  default_tags {
    tags = {
      Project     = "uptimekuma"
      Environment = "portfolio"
      ManagedBy   = "Terraform"
      Purpose     = "Persistent application backups"
    }
  }
}
