resource "aws_dynamodb_table" "notes" {
  name         = "${var.name_prefix}-notes"
  billing_mode = "PAY_PER_REQUEST" # pay per request, ~free at practice volume
  hash_key     = "pk"

  attribute {
    name = "pk"
    type = "S"
  }
}
