# Python and Go Lambda functions + build artifacts
# Python lambda packaging
# tflint-ignore: terraform_required_providers

# data "archive_file" "python_zip" {
#   type        = "zip"
#   source_dir  = "${path.module}/lambda/"
#   output_path = "${path.module}/lambda/lambda-trigger-sm.zip"
# }

# resource "aws_lambda_function" "upload_trigger_lambda" {
#   # checkov:skip=CKV_AWS_117
#   # checkov:skip=CKV_AWS_116
#   # checkov:skip=CKV_AWS_173
#   # checkov:skip=CKV_AWS_272
#   # checkov:skip=CKV_AWS_115
#   function_name = var.lambda_name
#   handler       = "index.lambda_handler"
#   runtime       = "python3.8"
#   role          = aws_iam_role.lambda_execution_role.arn
#   filename         = data.archive_file.python_zip.output_path
#   source_code_hash = data.archive_file.python_zip.output_base64sha256
#   timeout          = 120
#   tracing_config { mode = "Active" }
#   environment { variables = { SM_ARN = aws_sfn_state_machine.dynamodb_updater_workflow.arn } }
# }

# resource "aws_cloudwatch_log_group" "MyLambdaLogGroup" {
#   # checkov:skip=CKV_AWS_338
#   # checkov:skip=CKV_AWS_158
#   retention_in_days = 1
#   name              = "/aws/lambda/${aws_lambda_function.upload_trigger_lambda.function_name}"
# }

# Go lambda build
resource "null_resource" "build_go_lambda" {
  triggers = { source_hash = filesha256("${path.module}/../main.go") }
  provisioner "local-exec" {
    command     = "GOOS=linux GOARCH=amd64 go build -o hello ../main.go"
    working_dir = path.module
  }
}

# Build rate lambda
resource "null_resource" "build_rate_lambda" {
  triggers = { source_hash = filesha256("${path.module}/../cmd/rate/main.go") }
  provisioner "local-exec" {
    command     = "GOOS=linux GOARCH=amd64 go build -o rate ../cmd/rate/main.go"
    working_dir = path.module
  }
}

data "archive_file" "rate_lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/rate"
  output_path = "${path.module}/rate-lambda.zip"
  depends_on  = [null_resource.build_rate_lambda]
}

resource "aws_lambda_function" "rate_lambda" {
  function_name = var.rate_lambda_name
  handler       = "rate"
  runtime       = "go1.x"
  role          = aws_iam_role.lambda_execution_role.arn
  filename         = data.archive_file.rate_lambda_zip.output_path
  source_code_hash = data.archive_file.rate_lambda_zip.output_base64sha256
  timeout          = 3
  environment { variables = { STATIC_RATE = "1.10", STATIC_FEE_BPS = "25" } }
}

resource "aws_cloudwatch_log_group" "RateLambdaLogGroup" {
  name              = "/aws/lambda/${aws_lambda_function.rate_lambda.function_name}"
  retention_in_days = 1
}

# Build consumer lambda
resource "null_resource" "build_consumer_lambda" {
  triggers = { source_hash = filesha256("${path.module}/../cmd/consumer/main.go") }
  provisioner "local-exec" {
    command     = "GOOS=linux GOARCH=amd64 go build -o consumer ../cmd/consumer/main.go"
    working_dir = path.module
  }
}

# Build exchange lambda
resource "null_resource" "build_exchange_lambda" {
  triggers = { source_hash = filesha256("${path.module}/../cmd/exchange/main.go") }
  provisioner "local-exec" {
    command     = "GOOS=linux GOARCH=amd64 go build -o exchange ../cmd/exchange/main.go"
    working_dir = path.module
  }
}

data "archive_file" "exchange_lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/exchange"
  output_path = "${path.module}/exchange-lambda.zip"
  depends_on  = [null_resource.build_exchange_lambda]
}

resource "aws_lambda_function" "exchange_lambda" {
  function_name = "exchange_lambda"
  handler       = "exchange"
  runtime       = "go1.x"
  role          = aws_iam_role.lambda_execution_role.arn
  filename         = data.archive_file.exchange_lambda_zip.output_path
  source_code_hash = data.archive_file.exchange_lambda_zip.output_base64sha256
  timeout          = 10
  environment {
    variables = {
      DB_HOST     = var.db_host
      DB_PORT     = tostring(var.db_port)
      DB_USER     = var.db_username
      DB_PASSWORD = var.db_password
      DB_NAME     = var.db_name
    }
  }
}

resource "null_resource" "build_balances_lambda" {
  triggers = { source_hash = filesha256("${path.module}/../cmd/balances/main.go") }
  provisioner "local-exec" {
    command     = "GOOS=linux GOARCH=amd64 go build -o balances ../cmd/balances/main.go"
    working_dir = path.module
  }
}

data "archive_file" "balances_lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/balances"
  output_path = "${path.module}/balances-lambda.zip"
  depends_on  = [null_resource.build_balances_lambda]
}

resource "aws_lambda_function" "balances_lambda" {
  function_name = "balances_lambda"
  handler       = "balances"
  runtime       = "go1.x"
  role          = aws_iam_role.lambda_execution_role.arn
  filename         = data.archive_file.balances_lambda_zip.output_path
  source_code_hash = data.archive_file.balances_lambda_zip.output_base64sha256
  timeout          = 5
  environment {
    variables = {
      DB_HOST     = var.db_host
      DB_PORT     = tostring(var.db_port)
      DB_USER     = var.db_username
      DB_PASSWORD = var.db_password
      DB_NAME     = var.db_name
    }
  }
}

data "archive_file" "consumer_lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/consumer"
  output_path = "${path.module}/consumer-lambda.zip"
  depends_on  = [null_resource.build_consumer_lambda]
}

resource "aws_lambda_function" "consumer_lambda" {
  function_name = var.consumer_lambda_name
  handler       = "consumer"
  runtime       = "go1.x"
  role          = aws_iam_role.lambda_execution_role.arn
  filename         = data.archive_file.consumer_lambda_zip.output_path
  source_code_hash = data.archive_file.consumer_lambda_zip.output_base64sha256
  timeout          = 10
  environment {
    variables = {
      DB_HOST          = var.db_host
      DB_PORT          = tostring(var.db_port)
      DB_USER          = var.db_username
      DB_PASSWORD      = var.db_password
      DB_NAME          = var.db_name
      RATE_LAMBDA_NAME = var.rate_lambda_name
    }
  }
}

resource "aws_cloudwatch_log_group" "ConsumerLambdaLogGroup" {
  name              = "/aws/lambda/${aws_lambda_function.consumer_lambda.function_name}"
  retention_in_days = 1
}

# tflint-ignore: terraform_required_providers
data "archive_file" "go_lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/hello"
  output_path = "${path.module}/hello-lambda.zip"
  depends_on  = [null_resource.build_go_lambda]
}

resource "aws_lambda_function" "create_job_lambda" {
  function_name = var.go_lambda_name
  handler       = "hello"
  runtime       = "go1.x"
  role          = aws_iam_role.lambda_execution_role.arn
  filename         = data.archive_file.go_lambda_zip.output_path
  source_code_hash = data.archive_file.go_lambda_zip.output_base64sha256
  timeout          = 10
  #  To inherit X-Ray tracing from API Gateway, otherwise use "Active"
  tracing_config { mode = "PassThrough" }
  environment {
    variables = {
      DB_HOST     = var.db_host
      DB_PORT     = tostring(var.db_port)
      DB_USER     = var.db_username
      DB_PASSWORD = var.db_password
      DB_NAME     = var.db_name
      QUEUE_URL   = aws_sqs_queue.outbox.id
    }
  }
}

resource "aws_cloudwatch_log_group" "GoHelloLambdaLogGroup" {
  name              = "/aws/lambda/${aws_lambda_function.create_job_lambda.function_name}"
  retention_in_days = 1
}
