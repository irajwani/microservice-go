# IAM roles and policies for Lambdas and Step Functions

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "lambda_execution_role" {
  name               = "lambda_execution_role"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

# Allow basic CloudWatch Logs
data "aws_iam_policy_document" "logs_basic" {
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "logs_basic" {
  name   = "lambda-logs-basic"
  policy = data.aws_iam_policy_document.logs_basic.json
}

resource "aws_iam_role_policy_attachment" "lambda_logs_attach" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = aws_iam_policy.logs_basic.arn
}

# SQS consume permissions for consumer lambda
data "aws_iam_policy_document" "sqs_consume" {
  statement {
    effect = "Allow"
    actions = ["sqs:ReceiveMessage","sqs:DeleteMessage","sqs:GetQueueAttributes"]
    resources = [aws_sqs_queue.outbox.arn]
  }
}

resource "aws_iam_policy" "lambda_sqs_consume" {
  name   = "lambda-sqs-consume"
  policy = data.aws_iam_policy_document.sqs_consume.json
}

resource "aws_iam_role_policy_attachment" "lambda_attach_sqs_consume" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = aws_iam_policy.lambda_sqs_consume.arn
}

# Allow consumer to invoke rate lambda
data "aws_iam_policy_document" "lambda_invoke" {
  statement {
    effect = "Allow"
    actions = ["lambda:InvokeFunction"]
    resources = [aws_lambda_function.rate_lambda.arn]
  }
}

resource "aws_iam_policy" "lambda_invoke_rate" {
  name   = "lambda-invoke-rate"
  policy = data.aws_iam_policy_document.lambda_invoke.json
}

resource "aws_iam_role_policy_attachment" "lambda_attach_invoke_rate" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = aws_iam_policy.lambda_invoke_rate.arn
}
