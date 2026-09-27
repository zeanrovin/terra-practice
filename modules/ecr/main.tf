resource "aws_ecr_repository" "this" {
  for_each = var.repositories

  name                 = "${var.name_prefix}/${each.key}" # e.g. notes-dev/api
  image_tag_mutability = "MUTABLE"
  force_delete         = true # practice only: lets destroy remove repos that still hold images

  image_scanning_configuration {
    scan_on_push = true
  }
}

# Keep only the 5 newest images per repo so storage doesn't grow forever
resource "aws_ecr_lifecycle_policy" "this" {
  for_each   = aws_ecr_repository.this
  repository = each.value.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 5 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 5
      }
      action = { type = "expire" }
    }]
  })
}
