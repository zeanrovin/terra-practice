# Creates the S3 bucket that stores Terraform state for everything else.
# Chicken-and-egg: this folder itself uses LOCAL state (terraform.tfstate here, git-ignored).
# Run once: terraform init && terraform apply

terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "us-west-2"
}

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "state" {
  bucket        = "terra-practice-tfstate-${data.aws_caller_identity.current.account_id}"
  force_destroy = true # practice account only: lets you delete the bucket even with state files in it
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled" # keeps old state versions so you can recover from mistakes
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

output "state_bucket" {
  value = aws_s3_bucket.state.bucket
}
