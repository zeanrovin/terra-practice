# A module's inputs. The caller must pass every variable that has no default.

variable "name_prefix" {
  type = string
}

variable "service" {
  type = string
}

variable "port" {
  type    = number
  default = 0
}
