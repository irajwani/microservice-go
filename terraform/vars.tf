# Define variables
# variable "s3_bucket_name" {
#   description = "The name of the S3 bucket"
#   type        = string
#   default     = "my-test-bucket"
# }

# variable "dynamodb_table_name" {
#   description = "The name of the DynamoDB table"
#   type        = string
#   default     = "Files"
# }

# variable "dynamodb_hash_key" {
#   description = "The hash key of the DynamoDB table"
#   type        = string
#   default     = "FileName"
# }

# variable "lambda_name" {
#   description = "The name of the Lambda function"
#   type        = string
#   default     = "upload_trigger_lambda"
# }


# variable "s3_object_key" {
#   description = "The key of the S3 object"
#   type        = string
#   default     = "README.md"
# }

# variable "sfn_name" {
#   description = "The name of the Step Functions state machine"
#   type        = string
#   default     = "UploadStateMachine"
# }

variable "go_lambda_name" {
  description = "Name of the Go hello world lambda"
  type        = string
  default     = "hello_go_lambda"
}

variable "hello_api_name" {
  description = "Name of the HTTP API for hello lambda"
  type        = string
  default     = "hello_go_api"
}

variable "aws_region" {
  description = "AWS region (must match provider region)"
  type        = string
  default     = "eu-central-1"
}

variable "rest_api_name" {
  description = "Name of REST API (v1) for currency jobs"
  type        = string
  default     = "currency-jobs-api"
}

variable "rest_api_stage" {
  description = "Stage name for REST API deployment"
  type        = string
  default     = "dev"
}

variable "db_username" {
  description = "RDS master username"
  type        = string
  default     = "postgres"
}

variable "db_password" {
  description = "RDS master password (do NOT use default in real env)"
  type        = string
  default     = "postgrespw"
  sensitive   = true
}

variable "db_name" {
  description = "Database name"
  type        = string
  default     = "jobsdb"
}

variable "db_host" {
  description = "Database host (docker service name in compose)"
  type        = string
  default     = "postgres"
}

variable "db_port" {
  description = "Database port"
  type        = number
  default     = 5432
}

variable "outbox_queue_name" {
  description = "SQS queue name for transactional outbox dispatch"
  type        = string
  default     = "jobs-outbox-queue"
}

variable "rate_lambda_name" {
  description = "FX rate service lambda name"
  type        = string
  default     = "rate_service_lambda"
}

variable "consumer_lambda_name" {
  description = "Queue consumer lambda name"
  type        = string
  default     = "jobs_consumer_lambda"
}
