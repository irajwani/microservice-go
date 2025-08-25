# # Timing and DynamoDB read-after-write validation
# resource "time_sleep" "wait" {
#   create_duration = "55s"
#   triggers = { s3_object = local.key_json }
# }

# data "aws_dynamodb_table_item" "test" {
#   table_name = var.dynamodb_table_name
#   key        = time_sleep.wait.triggers.s3_object
# }

# locals {
#   key_json = jsonencode({
#     "FileName" = { "S" = aws_s3_object.object.key }
#   })
#   # tflint-ignore: terraform_unused_declarations
#   first_decode = jsondecode(data.aws_dynamodb_table_item.test.item)
# }
