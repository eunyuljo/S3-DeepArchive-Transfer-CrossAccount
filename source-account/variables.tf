variable "aws_region" {
  description = "AWS Region for Source account"
  type        = string
  default     = "ap-northeast-2"
}

variable "aws_profile" {
  description = "AWS CLI profile name for Source account"
  type        = string
  default     = "default"
}

variable "source_bucket_name" {
  description = "Name of the source S3 bucket (must be globally unique)"
  type        = string
  default     = "deep-archive-source-bucket"
}

variable "target_account_id" {
  description = "Target AWS Account ID for cross-account access"
  type        = string
  # 실제 사용 시 target account ID로 변경
  default     = "123456789012"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "test"
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
