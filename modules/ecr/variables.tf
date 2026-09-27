variable "name_prefix" {
  type = string
}

variable "repositories" {
  description = "One ECR repo per image name, e.g. [\"web\", \"api\", \"worker\"]"
  type        = set(string)
}
