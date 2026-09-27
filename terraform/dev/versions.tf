terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Settings come from backend.hcl: terraform init -backend-config=backend.hcl
  # (backend blocks can't use variables, which is one of the problems Terragrunt solves)
  backend "s3" {}
}
