output "target_bucket_name" {
  description = "Name of the target S3 bucket"
  value       = aws_s3_bucket.target.id
}

output "target_bucket_arn" {
  description = "ARN of the target S3 bucket"
  value       = aws_s3_bucket.target.arn
}

output "target_bucket_region" {
  description = "Region of the target S3 bucket"
  value       = aws_s3_bucket.target.region
}

output "iam_role_arn" {
  description = "ARN of the IAM role for cross-account access"
  value       = aws_iam_role.s3_cross_account.arn
}

output "iam_user_name" {
  description = "Name of the IAM user (if created)"
  value       = var.create_iam_user ? aws_iam_user.s3_copy_user[0].name : "N/A"
}

output "iam_user_access_key" {
  description = "Access key for IAM user (if created)"
  value       = var.create_iam_user ? aws_iam_access_key.s3_copy_user[0].id : "N/A"
  sensitive   = true
}

output "iam_user_secret_key" {
  description = "Secret key for IAM user (if created)"
  value       = var.create_iam_user ? aws_iam_access_key.s3_copy_user[0].secret : "N/A"
  sensitive   = true
}

output "source_bucket_policy_check" {
  description = "Command to verify source bucket policy"
  value       = "aws s3api get-bucket-policy --bucket ${var.source_bucket_name} --query Policy --output text | jq"
}

output "copy_command_example" {
  description = "Example AWS CLI command to copy from source to target"
  value       = <<-EOT
    # 1. First restore the object from Deep Archive:
    aws s3api restore-object \
        --bucket ${var.source_bucket_name} \
        --key deep-archive/yourfile.txt \
        --restore-request Days=7,GlacierJobParameters={Tier=Bulk}

    # 2. Wait for restore to complete (check status):
    aws s3api head-object \
        --bucket ${var.source_bucket_name} \
        --key deep-archive/yourfile.txt

    # 3. Copy to target bucket:
    aws s3 cp \
        s3://${var.source_bucket_name}/deep-archive/yourfile.txt \
        s3://${aws_s3_bucket.target.id}/restored/yourfile.txt
  EOT
}

output "instructions" {
  description = "Next steps"
  value       = <<-EOT
    Target account setup complete!

    Configuration Summary:
    - Target Bucket: ${aws_s3_bucket.target.id}
    - IAM Role: ${aws_iam_role.s3_cross_account.name}
    - Source Bucket: ${var.source_bucket_name}
    - Region: ${aws_s3_bucket.target.region}

    Next steps:
    1. Verify source bucket policy allows access from this account
    2. Configure AWS CLI with credentials (if using IAM user)
    3. Run test scripts: cd ../scripts && ./01-upload-to-deep-archive.sh

    To get sensitive outputs:
    terraform output -json iam_user_access_key
    terraform output -json iam_user_secret_key
  EOT
}

output "current_account_id" {
  description = "Current AWS Account ID"
  value       = data.aws_caller_identity.current.account_id
}
