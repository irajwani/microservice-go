# REST API Gateway for POST /jobs to Go lambda
resource "aws_api_gateway_rest_api" "jobs_api" {
  name = var.rest_api_name
  endpoint_configuration { types = ["EDGE"] }
}

resource "aws_api_gateway_resource" "jobs" {
  rest_api_id = aws_api_gateway_rest_api.jobs_api.id
  parent_id   = aws_api_gateway_rest_api.jobs_api.root_resource_id
  path_part   = "jobs"
}

resource "aws_api_gateway_resource" "exchange" {
  rest_api_id = aws_api_gateway_rest_api.jobs_api.id
  parent_id   = aws_api_gateway_rest_api.jobs_api.root_resource_id
  path_part   = "exchange"
}

resource "aws_api_gateway_resource" "balances" {
  rest_api_id = aws_api_gateway_rest_api.jobs_api.id
  parent_id   = aws_api_gateway_rest_api.jobs_api.root_resource_id
  path_part   = "balances"
}

resource "aws_api_gateway_resource" "job_item" {
  rest_api_id = aws_api_gateway_rest_api.jobs_api.id
  parent_id   = aws_api_gateway_resource.jobs.id
  path_part   = "{job_id}"
}

resource "aws_api_gateway_method" "jobs_post" {
  rest_api_id   = aws_api_gateway_rest_api.jobs_api.id
  resource_id   = aws_api_gateway_resource.jobs.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "exchange_post" {
  rest_api_id   = aws_api_gateway_rest_api.jobs_api.id
  resource_id   = aws_api_gateway_resource.exchange.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "balances_get" {
  rest_api_id   = aws_api_gateway_rest_api.jobs_api.id
  resource_id   = aws_api_gateway_resource.balances.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "jobdetail_get" {
  rest_api_id   = aws_api_gateway_rest_api.jobs_api.id
  resource_id   = aws_api_gateway_resource.job_item.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "jobs_list_get" {
  rest_api_id   = aws_api_gateway_rest_api.jobs_api.id
  resource_id   = aws_api_gateway_resource.jobs.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "jobs_post_integration" {
  rest_api_id             = aws_api_gateway_rest_api.jobs_api.id
  resource_id             = aws_api_gateway_resource.jobs.id
  http_method             = aws_api_gateway_method.jobs_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = "arn:aws:apigateway:${var.aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.create_job_lambda.arn}/invocations"
}

resource "aws_api_gateway_integration" "exchange_post_integration" {
  rest_api_id             = aws_api_gateway_rest_api.jobs_api.id
  resource_id             = aws_api_gateway_resource.exchange.id
  http_method             = aws_api_gateway_method.exchange_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = "arn:aws:apigateway:${var.aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.exchange_lambda.arn}/invocations"
}

resource "aws_api_gateway_integration" "balances_get_integration" {
  rest_api_id             = aws_api_gateway_rest_api.jobs_api.id
  resource_id             = aws_api_gateway_resource.balances.id
  http_method             = aws_api_gateway_method.balances_get.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = "arn:aws:apigateway:${var.aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.balances_lambda.arn}/invocations"
}

resource "aws_api_gateway_integration" "jobdetail_get_integration" {
  rest_api_id             = aws_api_gateway_rest_api.jobs_api.id
  resource_id             = aws_api_gateway_resource.job_item.id
  http_method             = aws_api_gateway_method.jobdetail_get.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = "arn:aws:apigateway:${var.aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.jobdetail_lambda.arn}/invocations"
}

resource "aws_api_gateway_integration" "jobs_list_get_integration" {
  rest_api_id             = aws_api_gateway_rest_api.jobs_api.id
  resource_id             = aws_api_gateway_resource.jobs.id
  http_method             = aws_api_gateway_method.jobs_list_get.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = "arn:aws:apigateway:${var.aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.jobdetail_lambda.arn}/invocations"
}

resource "aws_lambda_permission" "apigw_rest_invoke_go" {
  statement_id  = "AllowAPIGatewayRestInvokeGo"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.create_job_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${var.aws_region}:000000000000:${aws_api_gateway_rest_api.jobs_api.id}/*/POST/jobs"
}

resource "aws_lambda_permission" "apigw_rest_invoke_exchange" {
  statement_id  = "AllowAPIGatewayRestInvokeExchange"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.exchange_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${var.aws_region}:000000000000:${aws_api_gateway_rest_api.jobs_api.id}/*/POST/exchange"
}

resource "aws_lambda_permission" "apigw_rest_invoke_balances" {
  statement_id  = "AllowAPIGatewayRestInvokeBalances"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.balances_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${var.aws_region}:000000000000:${aws_api_gateway_rest_api.jobs_api.id}/*/GET/balances"
}

resource "aws_lambda_permission" "apigw_rest_invoke_jobdetail" {
  statement_id  = "AllowAPIGatewayRestInvokeJobDetail"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.jobdetail_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${var.aws_region}:000000000000:${aws_api_gateway_rest_api.jobs_api.id}/*/GET/jobs/*"
}

resource "aws_lambda_permission" "apigw_rest_invoke_jobs_list" {
  statement_id  = "AllowAPIGatewayRestInvokeJobsList"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.jobdetail_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${var.aws_region}:000000000000:${aws_api_gateway_rest_api.jobs_api.id}/*/GET/jobs"
}

resource "aws_api_gateway_deployment" "jobs_deployment" {
  rest_api_id = aws_api_gateway_rest_api.jobs_api.id
  depends_on  = [
    aws_api_gateway_integration.jobs_post_integration,
    aws_api_gateway_integration.exchange_post_integration,
  aws_api_gateway_integration.balances_get_integration,
  aws_api_gateway_integration.jobdetail_get_integration,
  aws_api_gateway_integration.jobs_list_get_integration
  ]
  stage_name  = var.rest_api_stage
  triggers = {
    redeploy_hash = sha1(join(",", [
      aws_api_gateway_method.jobs_post.id,
      aws_api_gateway_integration.jobs_post_integration.id,
      aws_api_gateway_method.exchange_post.id,
      aws_api_gateway_integration.exchange_post_integration.id,
      aws_api_gateway_method.balances_get.id,
      aws_api_gateway_integration.balances_get_integration.id,
  aws_api_gateway_method.jobdetail_get.id,
  aws_api_gateway_integration.jobdetail_get_integration.id,
  aws_api_gateway_method.jobs_list_get.id,
  aws_api_gateway_integration.jobs_list_get_integration.id,
      aws_lambda_function.create_job_lambda.source_code_hash,
      aws_lambda_function.exchange_lambda.source_code_hash,
      aws_lambda_function.balances_lambda.source_code_hash,
  aws_lambda_function.jobdetail_lambda.source_code_hash,
    ]))
  }
}
