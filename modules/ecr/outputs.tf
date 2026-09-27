output "repository_urls" {
  description = "Map of image name => repo URL"
  value       = { for name, repo in aws_ecr_repository.this : name => repo.repository_url }
}
