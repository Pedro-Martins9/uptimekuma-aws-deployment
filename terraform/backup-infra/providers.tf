provider "aws" {
  region = "eu-west-1"

  allowed_account_ids = ["REPLACE_WITH_AWS_ACCOUNT_ID"]

  default_tags {
    tags = {
      Project     = "uptimekuma"
      Environment = "portfolio"
      ManagedBy   = "Terraform"
      Purpose     = "Persistent application backups"
    }
  }
}
