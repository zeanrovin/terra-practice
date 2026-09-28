# ANATOMY: outputs. Values the project prints after apply, and the values
# a module hands back to whoever called it (module.<name>.<output>).
# Read any of them later with: terraform output <name>

output "lesson_01_name_prefix" {
  value = local.name_prefix
}

output "lesson_02_lists" {
  value = {
    service_names = local.service_names
    first_service = local.first_service
    service_count = local.service_count
  }
}

output "lesson_03_maps" {
  value = {
    api_settings = local.api_settings
    api_port     = local.api_port
    worker_cpu   = local.worker_cpu
    web_cpu      = local.web_cpu
  }
}

output "lesson_04_for_list" {
  value = local.upper_names
}

output "lesson_05_for_map" {
  value = local.ports
}

output "lesson_06_filter" {
  value = {
    web_services      = keys(local.web_services)
    dynamodb_services = local.dynamodb_services
  }
}

output "lesson_07_conditional" {
  value = local.kinds
}

output "lesson_08_merge" {
  value = local.api_env
}

output "lesson_09_for_each" {
  value = { for name, r in terraform_data.role : name => r.output.name }
}

output "lesson_10_filtered_for_each" {
  value = { for name, p in terraform_data.dynamodb_policy : name => p.output }
}

output "lesson_11_module" {
  value = { for name, m in module.label : name => m.summary }
}

output "lesson_12_real_inventory" {
  value = keys(local.real_services)
}
