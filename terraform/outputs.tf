# # Output the S3 bucket name
# output "s3_bucket_name" {
#   value = aws_s3_bucket.my_bucket.id
# }

# output "state_machine_arn" {
#   value = aws_sfn_state_machine.dynamodb_updater_workflow.arn
# }

# output "lambda_arn" {
#   value = aws_lambda_function.upload_trigger_lambda.arn
# }

# output "file_name_check" {
#   value = jsondecode(data.aws_dynamodb_table_item.test.item)["FileName"]["S"]
# }

output "jobs_api_invoke_url" {
  value = "http://localhost:4566/restapis/${aws_api_gateway_rest_api.jobs_api.id}/${var.rest_api_stage}/_user_request_/jobs"
}

output "outbox_queue_url" {
  value = aws_sqs_queue.outbox.id
}

output "rate_lambda_name" {
  value = aws_lambda_function.rate_lambda.function_name
}

output "consumer_lambda_name" {
  value = aws_lambda_function.consumer_lambda.function_name
}
