# Sunday: plain Terraform. One root module wires all the modules together.
# Monday you'll replace this file with Terragrunt (live/dev/).

locals {
  env         = "dev"
  region      = "us-west-2"
  name_prefix = "notes-${local.env}"
  services    = yamldecode(file("${path.module}/../../services.yaml"))
}

provider "aws" {
  region = local.region
  default_tags {
    tags = {
      Project   = "notes"
      Env       = local.env
      ManagedBy = "terraform"
    }
  }
}

module "network" {
  source      = "../../modules/network"
  name_prefix = local.name_prefix
}

module "ecr" {
  source       = "../../modules/ecr"
  name_prefix  = local.name_prefix
  repositories = keys(local.services)
}

module "dynamodb" {
  source      = "../../modules/dynamodb"
  name_prefix = local.name_prefix
}

module "cluster" {
  source            = "../../modules/cluster"
  name_prefix       = local.name_prefix
  vpc_id            = module.network.vpc_id
  public_subnet_ids = module.network.public_subnet_ids
}

module "services" {
  source      = "../../modules/services"
  name_prefix = local.name_prefix
  region      = local.region
  services    = local.services
  image_tag   = var.image_tag

  repository_urls       = module.ecr.repository_urls
  vpc_id                = module.network.vpc_id
  private_subnet_ids    = module.network.private_subnet_ids
  cluster_arn           = module.cluster.cluster_arn
  listener_arn          = module.cluster.listener_arn
  alb_security_group_id = module.cluster.alb_security_group_id
  execution_role_arn    = module.cluster.execution_role_arn
  table_name            = module.dynamodb.table_name
  table_arn             = module.dynamodb.table_arn
}

variable "image_tag" {
  type    = string
  default = "v1"
}

output "app_url" {
  value = "http://${module.cluster.alb_dns_name}"
}

output "ecr_repositories" {
  value = module.ecr.repository_urls
}
