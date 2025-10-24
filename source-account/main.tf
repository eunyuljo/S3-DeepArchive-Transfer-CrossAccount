terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile  # AWS CLI profile 사용

  default_tags {
    tags = var.tags
  }
}

# Source S3 Bucket
resource "aws_s3_bucket" "source" {
  bucket = var.source_bucket_name

  tags = {
    Name        = var.source_bucket_name
    Environment = var.environment
    Role        = "Source"
  }
}

# Bucket Versioning (권장)
resource "aws_s3_bucket_versioning" "source" {
  bucket = aws_s3_bucket.source.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Bucket Encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "source" {
  bucket = aws_s3_bucket.source.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block Public Access
resource "aws_s3_bucket_public_access_block" "source" {
  bucket = aws_s3_bucket.source.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle Rule for Deep Archive
resource "aws_s3_bucket_lifecycle_configuration" "source" {
  bucket = aws_s3_bucket.source.id

  rule {
    id     = "move-to-deep-archive"
    status = "Enabled"

    # 즉시 Deep Archive로 전환하는 규칙
    transition {
      days          = 0
      storage_class = "DEEP_ARCHIVE"
    }

    # 선택적: 특정 prefix만 적용
    filter {
      prefix = "deep-archive/"
    }
  }

  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    # 전체 버킷에 적용
    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

# Cross-Account Access Bucket Policy
resource "aws_s3_bucket_policy" "source" {
  bucket = aws_s3_bucket.source.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCrossAccountRead"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.target_account_id}:root"
        }
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.source.arn,
          "${aws_s3_bucket.source.arn}/*"
        ]
      },
      {
        Sid    = "AllowCrossAccountRestoreStatus"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.target_account_id}:root"
        }
        Action = [
          "s3:RestoreObject",
          "s3:GetObjectVersionAttributes"
        ]
        Resource = "${aws_s3_bucket.source.arn}/*"
      }
    ]
  })
}

# CloudWatch Log Group for S3 access logs (선택사항)
resource "aws_cloudwatch_log_group" "s3_access_logs" {
  name              = "/aws/s3/${var.source_bucket_name}"
  retention_in_days = 7

  tags = {
    Name = "s3-access-logs"
  }
}

# S3 Bucket Notification (선택사항 - 복원 완료 알림)
resource "aws_s3_bucket_notification" "source" {
  bucket = aws_s3_bucket.source.id

  # 추후 SNS/SQS/Lambda와 연동 가능
  # lambda_function {
  #   lambda_function_arn = aws_lambda_function.restore_complete.arn
  #   events              = ["s3:ObjectRestore:Completed"]
  # }
}
