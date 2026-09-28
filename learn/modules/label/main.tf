# A tiny module: takes a service name and builds a label for it.
# Inside a module you can only see its own variables (var.), never the
# caller's locals. Everything it needs has to be passed in.

locals {
  full_name = "${var.name_prefix}-${var.service}"
  exposure  = var.port > 0 ? "port ${var.port} behind the load balancer" : "no port (background)"
}
