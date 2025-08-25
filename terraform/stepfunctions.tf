# # Step Functions state machine and logs
# resource "aws_cloudwatch_log_group" "MySFNLogGroup" {
#   # checkov:skip=CKV_AWS_338: "Test logs do not require retention for 1 year"
#   # checkov:skip=CKV_AWS_158: "Test logs do not require encrypted by KMS"
#   name_prefix       = "/aws/vendedlogs/states/${var.sfn_name}-"
#   retention_in_days = 1
# }

# resource "aws_sfn_state_machine" "dynamodb_updater_workflow" {
#   name = var.sfn_name
#   tracing_configuration { enabled = true }
#   definition = jsonencode({
#     Comment = "A Step Function that writes to DynamoDB",
#     StartAt = "Upload",
#     States = {
#       Upload = {
#         Type     = "Task",
#         Resource = "arn:aws:states:::dynamodb:putItem",
#         Parameters = {
#           "TableName": aws_dynamodb_table.files.name,
#           "Item": { "FileName": { "S.$": "$.fileName" } }
#         },
#         End = true
#       }
#     }
#   })
#   role_arn = aws_iam_role.step_function_role.arn
#   logging_configuration {
#     level                  = "ALL"
#     include_execution_data = true
#     log_destination        = "${aws_cloudwatch_log_group.MySFNLogGroup.arn}:*"
#   }
#   timeouts { create = "1m" }
# }
