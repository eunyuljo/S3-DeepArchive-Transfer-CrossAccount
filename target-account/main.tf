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

# Target S3 Bucket
resource "aws_s3_bucket" "target" {
  bucket = var.target_bucket_name

  tags = {
    Name        = var.target_bucket_name
    Environment = var.environment
    Role        = "Target"
  }
}

# Bucket Versioning
resource "aws_s3_bucket_versioning" "target" {
  bucket = aws_s3_bucket.target.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Bucket Encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "target" {
  bucket = aws_s3_bucket.target.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block Public Access
resource "aws_s3_bucket_public_access_block" "target" {
  bucket = aws_s3_bucket.target.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle Rule for Target Bucket (선택사항)
resource "aws_s3_bucket_lifecycle_configuration" "target" {
  bucket = aws_s3_bucket.target.id

  rule {
    id     = "intelligent-tiering"
    status = "Enabled"

    # 전체 버킷에 적용
    filter {}

    transition {
      days          = 30
      storage_class = "INTELLIGENT_TIERING"
    }

    transition {
      days          = 90
      storage_class = "GLACIER_IR"
    }
  }
}

# IAM Role for Cross-Account S3 Copy
resource "aws_iam_role" "s3_cross_account" {
  name = "s3-cross-account-copy-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      },
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "s3-cross-account-role"
  }
}

# IAM Policy for Source Bucket Access
resource "aws_iam_policy" "source_bucket_access" {
  name        = "source-bucket-read-policy"
  description = "Policy to read from source account S3 bucket"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ListSourceBucket"
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = "arn:aws:s3:::${var.source_bucket_name}"
      },
      {
        Sid    = "GetFromSourceBucket"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:GetObjectAttributes",
          "s3:GetObjectVersionAttributes"
        ]
        Resource = "arn:aws:s3:::${var.source_bucket_name}/*"
      },
      {
        Sid    = "RestoreSourceObjects"
        Effect = "Allow"
        Action = [
          "s3:RestoreObject"
        ]
        Resource = "arn:aws:s3:::${var.source_bucket_name}/*"
      }
    ]
  })
}

# IAM Policy for Target Bucket Access
resource "aws_iam_policy" "target_bucket_access" {
  name        = "target-bucket-write-policy"
  description = "Policy to write to target S3 bucket"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ListTargetBucket"
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.target.arn
      },
      {
        Sid    = "WriteToTargetBucket"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl",
          "s3:GetObject",
          "s3:DeleteObject"
        ]
        Resource = "${aws_s3_bucket.target.arn}/*"
      }
    ]
  })
}

# Attach policies to role
resource "aws_iam_role_policy_attachment" "source_access" {
  role       = aws_iam_role.s3_cross_account.name
  policy_arn = aws_iam_policy.source_bucket_access.arn
}

resource "aws_iam_role_policy_attachment" "target_access" {
  role       = aws_iam_role.s3_cross_account.name
  policy_arn = aws_iam_policy.target_bucket_access.arn
}

# IAM User for testing (선택사항)
resource "aws_iam_user" "s3_copy_user" {
  count = var.create_iam_user ? 1 : 0
  name  = "s3-cross-account-copy-user"

  tags = {
    Name = "s3-copy-user"
  }
}

resource "aws_iam_user_policy_attachment" "user_source_access" {
  count      = var.create_iam_user ? 1 : 0
  user       = aws_iam_user.s3_copy_user[0].name
  policy_arn = aws_iam_policy.source_bucket_access.arn
}

resource "aws_iam_user_policy_attachment" "user_target_access" {
  count      = var.create_iam_user ? 1 : 0
  user       = aws_iam_user.s3_copy_user[0].name
  policy_arn = aws_iam_policy.target_bucket_access.arn
}

# Access Key for IAM User (선택사항)
resource "aws_iam_access_key" "s3_copy_user" {
  count = var.create_iam_user ? 1 : 0
  user  = aws_iam_user.s3_copy_user[0].name
}

# Current account information
data "aws_caller_identity" "current" {}

# CloudWatch Log Group for monitoring
resource "aws_cloudwatch_log_group" "s3_copy_logs" {
  name              = "/aws/s3-copy/${var.target_bucket_name}"
  retention_in_days = 7

  tags = {
    Name = "s3-copy-logs"
  }
}
