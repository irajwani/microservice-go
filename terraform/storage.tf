# # S3 and object related resources
# resource "aws_s3_bucket" "my_bucket" {
#   # checkov:skip=CKV2_AWS_62: "Ensure S3 buckets should have event notifications enabled"
#   # checkov:skip=CKV_AWS_18: "Ensure the S3 bucket has access logging enabled"
#   # checkov:skip=CKV_AWS_144: "Ensure that S3 bucket has cross-region replication enabled"
#   # checkov:skip=CKV_AWS_145: "Ensure that S3 buckets are encrypted with KMS by default"
#   bucket = var.s3_bucket_name
# }

# resource "aws_s3_bucket_versioning" "my_bucket_versioning" {
#   bucket = aws_s3_bucket.my_bucket.id
#   versioning_configuration { status = "Enabled" }
# }

# resource "aws_s3_bucket_public_access_block" "my_bucket_policy" {
#   bucket                  = aws_s3_bucket.my_bucket.id
#   block_public_acls       = true
#   block_public_policy     = true
#   ignore_public_acls      = true
#   restrict_public_buckets = true
# }

# resource "aws_s3_bucket_server_side_encryption_configuration" "my_bucket_encryption" {
#   bucket = aws_s3_bucket.my_bucket.bucket
#   rule {
#     apply_server_side_encryption_by_default {
#       sse_algorithm = "AES256"
#     }
#   }
# }

# resource "aws_s3_bucket_lifecycle_configuration" "this" {
#   bucket = aws_s3_bucket.my_bucket.id
#   rule {
#     id = "retention-policy"
#     expiration {
#       days = 7
#     }
#     abort_incomplete_multipart_upload {
#       days_after_initiation = 7
#     }
#     status = "Enabled"
#   }
# }

# resource "aws_s3_object" "object" {
#   bucket     = var.s3_bucket_name
#   key        = var.s3_object_key
#   source     = "${path.root}/${var.s3_object_key}"
#   depends_on = [aws_s3_bucket.my_bucket, aws_s3_bucket_notification.bucket_notification]
# }
