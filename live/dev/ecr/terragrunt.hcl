include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/modules//ecr"
}

inputs = {
  # One repo per entry in the inventory
  repositories = keys(yamldecode(file("${get_repo_root()}/services.yaml")))
}
