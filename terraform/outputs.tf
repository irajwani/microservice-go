output "jobs_api_invoke_url" {
  value = "http://localhost:4566/restapis/${aws_api_gateway_rest_api.jobs_api.id}/${var.rest_api_stage}/_user_request_/jobs"
}

output "balances_api_invoke_url" {
  value = "http://localhost:4566/restapis/${aws_api_gateway_rest_api.jobs_api.id}/${var.rest_api_stage}/_user_request_/balances"
}

output "jobdetail_api_invoke_url" {
  value = "http://localhost:4566/restapis/${aws_api_gateway_rest_api.jobs_api.id}/${var.rest_api_stage}/_user_request_/jobs/{job_id}"
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
