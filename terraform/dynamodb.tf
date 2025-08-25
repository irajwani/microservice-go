# # DynamoDB table
# resource "aws_dynamodb_table" "files" {
#   # checkov:skip=CKV_AWS_119: "Test DynamoDB table does not need to be encrypted using a KMS Customer Managed CMK"
#   name         = var.dynamodb_table_name
#   billing_mode = "PAY_PER_REQUEST"
#   hash_key     = var.dynamodb_hash_key
#   attribute {
#     name = var.dynamodb_hash_key
#     type = "S"
#   }
#   point_in_time_recovery { enabled = true }
# }
