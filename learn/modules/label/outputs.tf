# What the caller can read, as module.label["api"].summary

output "summary" {
  value = "${local.full_name}: ${local.exposure}"
}
