# SQS queue for outbox publication (transactional outbox dispatcher target)
resource "aws_sqs_queue" "outbox" {
  name                      = var.outbox_queue_name
  visibility_timeout_seconds = 30
  message_retention_seconds  = 86400
  receive_wait_time_seconds  = 2
}

# (Optional future) DLQ
# resource "aws_sqs_queue" "outbox_dlq" {
#   name = "${var.outbox_queue_name}-dlq"
# }

# Policy snippet to allow Lambda to send messages
data "aws_iam_policy_document" "sqs_send" {
  statement {
    effect = "Allow"
    actions = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.outbox.arn]
  }
}

resource "aws_iam_policy" "lambda_sqs_send" {
  name        = "lambda-sqs-send"
  description = "Allow lambdas to send messages to outbox queue"
  policy      = data.aws_iam_policy_document.sqs_send.json
}

resource "aws_iam_role_policy_attachment" "lambda_attach_sqs_send" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = aws_iam_policy.lambda_sqs_send.arn
}

# Event source mapping: SQS -> consumer lambda
resource "aws_lambda_event_source_mapping" "outbox_consumer" {
  event_source_arn = aws_sqs_queue.outbox.arn
  function_name    = aws_lambda_function.consumer_lambda.arn
  batch_size       = 5
  enabled          = true
}
