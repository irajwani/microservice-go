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

# data "aws_iam_policy_document" "lambda_policy" {
#   statement {
#     effect = "Allow"
#     actions = ["logs:CreateLogStream","logs:PutLogEvents","logs:DescribeLogGroups"]
#     resources = ["${aws_cloudwatch_log_group.MyLambdaLogGroup.arn}:*"]
#   }
#   statement {
#     effect = "Allow"
#     actions = [
#       "cloudwatch:PutMetricData",
#       "logs:CreateLogDelivery","logs:GetLogDelivery","logs:UpdateLogDelivery","logs:DeleteLogDelivery","logs:ListLogDeliveries","logs:PutResourcePolicy","logs:DescribeResourcePolicies"
#     ]
#     resources = ["*"]
#   }
# }

# resource "aws_iam_policy" "lambda_policy" {
#   name        = "lambda_dynamodb_policy"
#   description = "Policy to allow Lambda to start a Step Function"
#   policy      = data.aws_iam_policy_document.lambda_policy.json
# }

# resource "aws_iam_role_policy_attachment" "lambda_dynamodb_attachment" {
#   policy_arn = aws_iam_policy.lambda_policy.arn
#   role       = aws_iam_role.lambda_execution_role.name
# }

# data "aws_iam_policy_document" "sf_policy" {
#   statement {
#     effect    = "Allow"
#     actions   = ["dynamodb:PutItem"]
#     resources = [aws_dynamodb_table.files.arn]
#   }
#   statement {
#     effect = "Allow"
#     actions = [
#       "logs:CreateLogDelivery","logs:GetLogDelivery","logs:UpdateLogDelivery","logs:DeleteLogDelivery","logs:ListLogDeliveries","logs:PutResourcePolicy","logs:DescribeResourcePolicies","logs:DescribeLogGroups"
#     ]
#     resources = ["*"]
#   }
# }

# resource "aws_iam_policy" "state_machine_policy" {
#   name        = "state_machine_policy"
#   description = "Policy to allow PutItem in DynamoDB and permissions for CloudWatch Logs"
#   policy      = data.aws_iam_policy_document.sf_policy.json
# }

# data "aws_iam_policy_document" "assume_role_sf" {
#   statement {
#     effect = "Allow"
#     principals {
#       type        = "Service"
#       identifiers = ["states.amazonaws.com"]
#     }
#     actions = ["sts:AssumeRole"]
#   }
# }

# resource "aws_iam_role" "step_function_role" {
#   name               = "step_function_role"
#   assume_role_policy = data.aws_iam_policy_document.assume_role_sf.json
# }

# resource "aws_iam_role_policy_attachment" "attach_state_machine_policy" {
#   policy_arn = aws_iam_policy.state_machine_policy.arn
#   role       = aws_iam_role.step_function_role.name
# }
