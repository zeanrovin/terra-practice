variable "name_prefix" {
  type = string
}

variable "region" {
  type = string
}

variable "services" {
  description = "The inventory from services.yaml: one entry per image"
  type = map(object({
    port              = optional(number, 0)
    cpu               = optional(number, 256)
    memory            = optional(number, 512)
    desired_count     = optional(number, 1)
    path_patterns     = optional(list(string), [])
    priority          = optional(number, 100)
    health_check_path = optional(string, "/")
    dynamodb_access   = optional(bool, false)
    environment       = optional(map(string), {})
  }))
}

variable "image_tag" {
  description = "Which image tag to deploy. Change it to roll out a new version."
  type        = string
  default     = "v1"
}

variable "repository_urls" {
  description = "Map of image name => ECR repo URL (from the ecr module)"
  type        = map(string)
}

variable "cpu_architecture" {
  description = "ARM64 matches images built on Apple Silicon (see scripts/push-images.sh)"
  type        = string
  default     = "ARM64"
}

# From the network module
variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

# From the cluster module
variable "cluster_arn" {
  type = string
}

variable "listener_arn" {
  type = string
}

variable "alb_security_group_id" {
  type = string
}

variable "execution_role_arn" {
  type = string
}

# From the dynamodb module
variable "table_name" {
  type = string
}

variable "table_arn" {
  type = string
}
