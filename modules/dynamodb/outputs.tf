output "table_name" {
  value = aws_dynamodb_table.notes.name
}

output "table_arn" {
  value = aws_dynamodb_table.notes.arn
}
