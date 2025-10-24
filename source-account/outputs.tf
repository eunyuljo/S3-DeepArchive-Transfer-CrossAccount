output "source_bucket_name" {
  description = "Name of the source S3 bucket"
  value       = aws_s3_bucket.source.id
}

output "source_bucket_arn" {
  description = "ARN of the source S3 bucket"
  value       = aws_s3_bucket.source.arn
}

output "source_bucket_region" {
  description = "Region of the source S3 bucket"
  value       = aws_s3_bucket.source.region
}

output "source_bucket_domain_name" {
  description = "Domain name of the source S3 bucket"
  value       = aws_s3_bucket.source.bucket_domain_name
}

output "instructions" {
  description = "Next steps"
  value       = <<-EOT
    Source account setup complete!

    Next steps:
    1. Note this bucket name: ${aws_s3_bucket.source.id}
    2. Update target-account/variables.tf with:
       - source_bucket_name = "${aws_s3_bucket.source.id}"
       - source_account_id = "<YOUR_SOURCE_ACCOUNT_ID>"
    3. Apply target account configuration
    4. Upload test data: cd ../scripts && ./01-upload-to-deep-archive.sh

    Bucket ARN: ${aws_s3_bucket.source.arn}
    Region: ${aws_s3_bucket.source.region}
  EOT
}
