# ANATOMY: the "terraform" block. Settings for Terraform itself, not for AWS.
#
# In terraform/dev/versions.tf this block also lists required_providers (aws)
# and a backend "s3" (where state is stored). This practice project needs
# neither: it only uses the built-in terraform_data resource, and with no
# backend the state is saved locally in learn/terraform.tfstate (git-ignored).

terraform {
  required_version = ">= 1.10"
}
