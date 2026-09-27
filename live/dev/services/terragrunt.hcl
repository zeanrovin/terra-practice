include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/modules//services"
}

dependency "network" {
  config_path = "../network"
  mock_outputs = {
    vpc_id             = "vpc-00000000"
    private_subnet_ids = ["subnet-00000003", "subnet-00000004"]
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

dependency "ecr" {
  config_path = "../ecr"
  mock_outputs = {
    repository_urls = { web = "mock/web", api = "mock/api", worker = "mock/worker" }
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

dependency "dynamodb" {
  config_path = "../dynamodb"
  mock_outputs = {
    table_name = "mock-table"
    table_arn  = "arn:aws:dynamodb:us-west-2:000000000000:table/mock-table"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

dependency "cluster" {
  config_path = "../cluster"
  mock_outputs = {
    cluster_arn           = "arn:aws:ecs:us-west-2:000000000000:cluster/mock"
    listener_arn          = "arn:aws:elasticloadbalancing:us-west-2:000000000000:listener/app/mock/0/0"
    alb_security_group_id = "sg-00000000"
    execution_role_arn    = "arn:aws:iam::000000000000:role/mock"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

inputs = {
  services  = yamldecode(file("${get_repo_root()}/services.yaml"))
  image_tag = "v1"

  repository_urls       = dependency.ecr.outputs.repository_urls
  vpc_id                = dependency.network.outputs.vpc_id
  private_subnet_ids    = dependency.network.outputs.private_subnet_ids
  cluster_arn           = dependency.cluster.outputs.cluster_arn
  listener_arn          = dependency.cluster.outputs.listener_arn
  alb_security_group_id = dependency.cluster.outputs.alb_security_group_id
  execution_role_arn    = dependency.cluster.outputs.execution_role_arn
  table_name            = dependency.dynamodb.outputs.table_name
  table_arn             = dependency.dynamodb.outputs.table_arn
}
