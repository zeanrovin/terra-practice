output "service_names" {
  value = [for s in aws_ecs_service.this : s.name]
}

output "log_groups" {
  value = { for name, lg in aws_cloudwatch_log_group.this : name => lg.name }
}
