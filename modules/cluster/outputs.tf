output "cluster_arn" {
  value = aws_ecs_cluster.this.arn
}

output "alb_dns_name" {
  value = aws_lb.this.dns_name
}

output "listener_arn" {
  value = aws_lb_listener.http.arn
}

output "alb_security_group_id" {
  value = aws_security_group.alb.id
}

output "execution_role_arn" {
  value = aws_iam_role.execution.arn
}
