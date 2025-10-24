variable "aws_region" {
  description = "AWS Region for Target account"
  type        = string
  default     = "ap-northeast-2"
}

variable "aws_profile" {
  description = "AWS CLI profile name for Target account"
  type        = string
  default     = "default"
}

variable "target_bucket_name" {
  description = "Name of the target S3 bucket (must be globally unique)"
  type        = string
  default     = "deep-archive-target-bucket"
}

variable "source_account_id" {
  description = "Source AWS Account ID"
  type        = string
  # 실제 사용 시 source account ID로 변경
  default     = "123456789012"
}

variable "source_bucket_name" {
  description = "Name of the source S3 bucket"
  type        = string
  # source-account terraform output에서 가져온 값으로 변경
  default     = "deep-archive-source-bucket"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "test"
}

variable "create_iam_user" {
  description = "Create IAM user for cross-account access testing"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default = {
    Project     = "S3-Deep-Archive-Transfer"
    ManagedBy   = "Terraform"
    Purpose     = "Testing"
  }
}
