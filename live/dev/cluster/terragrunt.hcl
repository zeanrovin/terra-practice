include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/modules//cluster"
}

# Read outputs from the network unit's state.
# mock_outputs let you run `plan` before network has been applied.
dependency "network" {
  config_path = "../network"

  mock_outputs = {
    vpc_id            = "vpc-00000000"
    public_subnet_ids = ["subnet-00000001", "subnet-00000002"]
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

inputs = {
  vpc_id            = dependency.network.outputs.vpc_id
  public_subnet_ids = dependency.network.outputs.public_subnet_ids
}
