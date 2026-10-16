
provider "aws" {
  region = "eu-west-1"

  # Prevent accidental deployment into another AWS account.
  allowed_account_ids = [var.aws_account_id]

  default_tags {
    tags = {
      Project     = "uptimekuma"
      Environment = "portfolio"
      ManagedBy   = "Terraform"
    }
  }
}
