include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/modules//network"
}

inputs = {
  cidr_block = "10.0.0.0/16"
}
