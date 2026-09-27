# Shared by every unit under live/. Each terragrunt.hcl pulls this in with `include "root"`.

locals {
  env_vars   = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  env        = local.env_vars.locals.env
  region     = local.env_vars.locals.region
  project    = "notes"
  account_id = get_aws_account_id()
}

# Remote state: one state file per unit, keyed by folder path.
# e.g. live/dev/network -> terragrunt/dev/network/terraform.tfstate
remote_state {
  backend = "s3"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  config = {
    bucket       = "terra-practice-tfstate-${local.account_id}"
    key          = "terragrunt/${path_relative_to_include()}/terraform.tfstate"
    region       = local.region
    encrypt      = true
    use_lockfile = true
  }
}

# Writes a provider.tf into every unit so modules don't need their own provider block
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOT
    provider "aws" {
      region = "${local.region}"
      default_tags {
        tags = {
          Project   = "${local.project}"
          Env       = "${local.env}"
          ManagedBy = "terragrunt"
        }
      }
    }
  EOT
}

# Passed to every unit (units ignore inputs their module doesn't declare)
inputs = {
  name_prefix = "${local.project}-${local.env}"
  region      = local.region
}
