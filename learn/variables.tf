# ANATOMY: inputs. Anything declared here is read as var.<name>.
# A default makes the variable optional. Without one, Terraform asks for it.
#
# Override from the command line:
#   terraform apply -var env=prod

variable "env" {
  description = "Environment name, used in every resource name"
  type        = string
  default     = "dev"
}

# The same shape as services.yaml, kept small so it's easy to follow.
# It's a MAP: key (the service name) => value (that service's settings).
variable "services" {
  description = "One entry per service"
  type = map(object({
    port            = number
    cpu             = optional(number, 256) # missing? use 256
    dynamodb_access = optional(bool, false) # missing? use false
  }))
  default = {
    web    = { port = 80 }
    api    = { port = 8080, dynamodb_access = true }
    worker = { port = 0, cpu = 512, dynamodb_access = true }
  }
}
