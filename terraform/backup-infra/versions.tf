terraform {
  required_version = ">= 1.12.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Intentional partial backend configuration. Supply the existing bucket
  # with terraform init -backend-config="bucket=<state-bucket-name>".
  backend "s3" {
    bucket       = ""
    key          = "uptimekuma/backup-infra.tfstate"
    region       = "eu-west-1"
    encrypt      = true
    use_lockfile = true
  }
}
