# Troubleshooting Guide

## Common Issues and Solutions

### 1. Access Denied Errors

#### Issue: Cannot list source bucket

```
An error occurred (AccessDenied) when calling the ListObjectsV2 operation: Access Denied
```

**Diagnosis:**

```bash
# Check your current identity
aws sts get-caller-identity

# Try to access the bucket
aws s3 ls s3://source-bucket/
```

**Solutions:**

**A. Check AWS Credentials**
```bash
# Verify credentials are configured
cat ~/.aws/credentials

# Check current profile
echo $AWS_PROFILE

# Switch profile if needed
export AWS_PROFILE=correct-profile
```

**B. Verify IAM Permissions**
```bash
# Check user permissions
aws iam get-user --user-name your-username

# List attached policies
aws iam list-attached-user-policies --user-name your-username

# Get policy details
aws iam get-policy-version \
    --policy-arn arn:aws:iam::ACCOUNT-ID:policy/POLICY-NAME \
    --version-id v1
```

**C. Check Bucket Policy**
```bash
# Get bucket policy
aws s3api get-bucket-policy --bucket source-bucket

# Verify it allows your account
# Should contain: "Principal": {"AWS": "arn:aws:iam::YOUR-ACCOUNT-ID:root"}
```

**Required IAM Policy for Source Bucket Access:**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket",
        "s3:GetBucketLocation"
      ],
      "Resource": "arn:aws:s3:::source-bucket"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:GetObjectVersion"
      ],
      "Resource": "arn:aws:s3:::source-bucket/*"
    }
  ]
}
```

#### Issue: Cross-account access denied

```
An error occurred (AccessDenied) when calling the GetObject operation
```

**Root Causes:**
1. Bucket policy doesn't allow target account
2. Target account doesn't have IAM permissions
3. Object ACL prevents access

**Solution:**

**Source Account - Bucket Policy:**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowCrossAccountRead",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::TARGET-ACCOUNT-ID:root"
      },
      "Action": [
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::source-bucket",
        "arn:aws:s3:::source-bucket/*"
      ]
    }
  ]
}
```

**Target Account - IAM Policy:**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::source-bucket",
        "arn:aws:s3:::source-bucket/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject"
      ],
      "Resource": "arn:aws:s3:::target-bucket/*"
    }
  ]
}
```

**Verification:**
```bash
# From target account, try to access source bucket
aws s3 ls s3://source-bucket/ --profile target-account

# If successful, should see objects
```

### 2. Restore Issues

#### Issue: InvalidObjectState

```
An error occurred (InvalidObjectState) when calling the GetObject operation:
The operation is not valid for the object's storage class
```

**Cause:** Trying to access a Deep Archive object that hasn't been restored.

**Solution:**

```bash
# 1. Check object storage class
aws s3api head-object \
    --bucket source-bucket \
    --key deep-archive/file.txt

# Look for: "StorageClass": "DEEP_ARCHIVE"

# 2. Initiate restore
aws s3api restore-object \
    --bucket source-bucket \
    --key deep-archive/file.txt \
    --restore-request Days=7,GlacierJobParameters={Tier=Bulk}

# 3. Check restore status
aws s3api head-object \
    --bucket source-bucket \
    --key deep-archive/file.txt \
    | grep Restore

# Wait for: "Restore": "ongoing-request=\"false\""
```

#### Issue: RestoreAlreadyInProgress

```
An error occurred (RestoreAlreadyInProgress) when calling the RestoreObject operation
```

**Cause:** Restore request already submitted for this object.

**Solution:**

This is not actually an error - just wait for the restore to complete.

```bash
# Check status
aws s3api head-object \
    --bucket source-bucket \
    --key deep-archive/file.txt \
    | grep Restore

# Possible outputs:
# 1. "ongoing-request=\"true\"" - Still restoring (wait)
# 2. "ongoing-request=\"false\", expiry-date=\"...\"" - Restored (ready to use)
```

**Monitor Progress:**

Create a monitoring script:

```bash
#!/bin/bash
while true; do
    STATUS=$(aws s3api head-object \
        --bucket source-bucket \
        --key deep-archive/file.txt \
        2>/dev/null | grep "ongoing-request" | grep -o "true\|false")

    if [ "$STATUS" = "false" ]; then
        echo "Restore complete!"
        break
    else
        echo "$(date): Still restoring..."
        sleep 300  # Check every 5 minutes
    fi
done
```

#### Issue: Restore taking longer than expected

**Expected Times:**
- Bulk: 12 hours
- Standard: 12 hours

**If longer:**

1. **Check Status:**
```bash
aws s3api head-object --bucket source-bucket --key file.txt | jq
```

2. **Verify Request Was Successful:**
```bash
# Check CloudTrail logs
aws cloudtrail lookup-events \
    --lookup-attributes AttributeKey=EventName,AttributeValue=RestoreObject \
    --max-results 10
```

3. **Contact AWS Support if > 24 hours**

### 3. Copy/Transfer Issues

#### Issue: Slow transfer speeds

**Diagnosis:**

```bash
# Test with a small file first
time aws s3 cp s3://source/test.txt s3://target/test.txt

# Check network connectivity
ping s3.amazonaws.com

# Check AWS CLI version
aws --version
```

**Solutions:**

**A. Use S3 Transfer Acceleration (for cross-region)**

```bash
# Enable on bucket
aws s3api put-bucket-accelerate-configuration \
    --bucket target-bucket \
    --accelerate-configuration Status=Enabled

# Use accelerated endpoint
aws s3 cp s3://source/file.txt s3://target/file.txt \
    --endpoint-url https://s3-accelerate.amazonaws.com
```

**B. Increase Max Concurrent Requests**

```bash
# Configure AWS CLI
aws configure set default.s3.max_concurrent_requests 20
aws configure set default.s3.max_bandwidth 100MB/s
```

**C. Use Multipart Upload**

```bash
# Configure threshold
aws configure set default.s3.multipart_threshold 64MB
aws configure set default.s3.multipart_chunksize 16MB
```

**D. Parallel Transfers with GNU Parallel**

```bash
# Install GNU parallel
# Ubuntu/Debian:
sudo apt-get install parallel

# macOS:
brew install parallel

# Parallel copy
aws s3 ls s3://source-bucket/deep-archive/ | \
    awk '{print $4}' | \
    parallel -j 4 aws s3 cp \
        s3://source-bucket/deep-archive/{} \
        s3://target-bucket/restored/{}
```

#### Issue: Copy fails with NoSuchKey

```
An error occurred (NoSuchKey) when calling the CopyObject operation: The specified key does not exist
```

**Solutions:**

```bash
# 1. Verify object exists
aws s3 ls s3://source-bucket/path/to/file.txt

# 2. Check for trailing slashes
# Wrong: s3://bucket/path/
# Right: s3://bucket/path/file.txt

# 3. URL encode special characters
# If filename has spaces: "my file.txt" → "my%20file.txt"
```

#### Issue: Copy fails with RequestTimeTooSkewed

```
An error occurred (RequestTimeTooSkewed) when calling the CopyObject operation
```

**Cause:** Your system clock is out of sync.

**Solution:**

```bash
# Linux
sudo ntpdate time.nist.gov
# or
sudo timedatectl set-ntp true

# macOS
sudo sntp -sS time.apple.com

# Windows
w32tm /resync
```

### 4. Storage Class Issues

#### Issue: Object still showing GLACIER or DEEP_ARCHIVE after restore

**This is expected!** Restored objects maintain their storage class but are temporarily accessible.

**Verification:**

```bash
aws s3api head-object \
    --bucket source-bucket \
    --key file.txt

# Look for both:
# "StorageClass": "DEEP_ARCHIVE"  ← Original class
# "Restore": "ongoing-request=\"false\""  ← Restored status
```

**If you need permanent Standard storage:**

```bash
# Copy object to change storage class
aws s3 cp \
    s3://bucket/file.txt \
    s3://bucket/file.txt \
    --storage-class STANDARD \
    --metadata-directive COPY
```

#### Issue: Lifecycle policy moving objects too quickly

**Symptom:** Objects transition to Deep Archive before you can test.

**Solution:**

**A. Modify Lifecycle Rule:**

```bash
# Get current lifecycle configuration
aws s3api get-bucket-lifecycle-configuration \
    --bucket source-bucket \
    > lifecycle.json

# Edit lifecycle.json to change days or disable rule

# Update lifecycle
aws s3api put-bucket-lifecycle-configuration \
    --bucket source-bucket \
    --lifecycle-configuration file://lifecycle.json
```

**B. Use Different Prefix for Testing:**

```bash
# Upload to a prefix without lifecycle rules
aws s3 cp test.txt s3://source-bucket/testing/test.txt \
    --storage-class STANDARD
```

### 5. Terraform Issues

#### Issue: Bucket already exists

```
Error: Error creating S3 bucket: BucketAlreadyExists: The requested bucket name is not available
```

**Cause:** S3 bucket names are globally unique.

**Solution:**

```bash
# Add unique suffix to bucket name
# In terraform.tfvars:
source_bucket_name = "deep-archive-source-${random_id}"

# Or use timestamp
source_bucket_name = "deep-archive-source-$(date +%Y%m%d%H%M%S)"
```

#### Issue: Terraform can't destroy bucket (not empty)

```
Error: Error deleting S3 bucket: BucketNotEmpty: The bucket you tried to delete is not empty
```

**Solution:**

```bash
# 1. Empty the bucket first
aws s3 rm s3://bucket-name/ --recursive

# 2. Delete versioned objects
aws s3api list-object-versions \
    --bucket bucket-name \
    --output json | \
    jq '.Versions[] | {Key: .Key, VersionId: .VersionId}' | \
    jq -s '.' | \
    jq '{Objects: .}' > delete.json

aws s3api delete-objects \
    --bucket bucket-name \
    --delete file://delete.json

# 3. Delete delete markers
aws s3api list-object-versions \
    --bucket bucket-name \
    --output json | \
    jq '.DeleteMarkers[] | {Key: .Key, VersionId: .VersionId}' | \
    jq -s '.' | \
    jq '{Objects: .}' > delete-markers.json

aws s3api delete-objects \
    --bucket bucket-name \
    --delete file://delete-markers.json

# 4. Now destroy with Terraform
terraform destroy
```

#### Issue: Terraform state locked

```
Error: Error locking state: Error acquiring the state lock
```

**Solution:**

```bash
# Force unlock (use with caution)
terraform force-unlock LOCK_ID

# Or delete lock table if using DynamoDB backend
aws dynamodb delete-item \
    --table-name terraform-lock \
    --key '{"LockID": {"S": "PATH/TO/terraform.tfstate"}}'
```

### 6. Cost Issues

#### Issue: Unexpected high costs

**Diagnosis:**

```bash
# Check AWS Cost Explorer
aws ce get-cost-and-usage \
    --time-period Start=2024-01-01,End=2024-01-31 \
    --granularity MONTHLY \
    --metrics UnblendedCost \
    --group-by Type=SERVICE

# Detailed S3 costs
aws ce get-cost-and-usage \
    --time-period Start=2024-01-01,End=2024-01-31 \
    --granularity MONTHLY \
    --metrics UnblendedCost \
    --filter file://filter.json

# filter.json:
{
  "Dimensions": {
    "Key": "SERVICE",
    "Values": ["Amazon Simple Storage Service"]
  }
}
```

**Common Causes:**

1. **Early deletion from Deep Archive** (180-day minimum)
   - Solution: Keep objects for full 180 days or longer

2. **Using Standard restore instead of Bulk**
   - Solution: Use Bulk tier (75% cheaper)

3. **Cross-region data transfer**
   - Solution: Keep source and target in same region

4. **Multiple restore attempts**
   - Solution: Check restore status before retrying

5. **Long restore retention period**
   - Solution: Use minimum days needed (1-7 days typically)

**Cost Reduction:**

```bash
# Set up cost alert
aws cloudwatch put-metric-alarm \
    --alarm-name s3-cost-alert \
    --alarm-description "Alert when S3 costs exceed $100" \
    --metric-name EstimatedCharges \
    --namespace AWS/Billing \
    --statistic Maximum \
    --period 21600 \
    --evaluation-periods 1 \
    --threshold 100 \
    --comparison-operator GreaterThanThreshold \
    --dimensions Name=ServiceName,Value=AmazonS3
```

### 7. Script Issues

#### Issue: Script fails with "command not found"

```bash
# Install missing dependencies

# AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# jq
sudo apt-get install jq  # Ubuntu/Debian
sudo yum install jq      # Amazon Linux/RHEL
brew install jq          # macOS
```

#### Issue: Permission denied on scripts

```bash
# Make scripts executable
chmod +x scripts/*.sh

# Or individually
chmod +x scripts/01-upload-to-deep-archive.sh
```

#### Issue: Bash script syntax errors on macOS

**Cause:** macOS uses BSD utilities instead of GNU.

**Solution:**

```bash
# Install GNU utilities
brew install coreutils findutils gnu-sed

# Add to PATH in ~/.zshrc or ~/.bash_profile
export PATH="/usr/local/opt/coreutils/libexec/gnubin:$PATH"

# Or use Linux container
docker run -it --rm -v $(pwd):/work amazonlinux:2 bash
cd /work
./scripts/01-upload-to-deep-archive.sh
```

### 8. Verification and Debugging

#### Enable AWS CLI Debug Mode

```bash
# Verbose output
aws s3 cp file.txt s3://bucket/ --debug

# Save debug output
aws s3 cp file.txt s3://bucket/ --debug 2> debug.log
```

#### Check S3 Server Access Logs

```bash
# Enable logging on source bucket
aws s3api put-bucket-logging \
    --bucket source-bucket \
    --bucket-logging-status '{
      "LoggingEnabled": {
        "TargetBucket": "log-bucket",
        "TargetPrefix": "source-bucket-logs/"
      }
    }'

# View logs
aws s3 ls s3://log-bucket/source-bucket-logs/
aws s3 cp s3://log-bucket/source-bucket-logs/2024-01-01-00-00-00-ABC123 - | less
```

#### Check CloudTrail Events

```bash
# Recent S3 events
aws cloudtrail lookup-events \
    --lookup-attributes AttributeKey=ResourceType,AttributeValue=AWS::S3::Object \
    --max-results 50 \
    | jq '.Events[] | {time: .EventTime, name: .EventName, user: .Username}'

# Specific bucket events
aws cloudtrail lookup-events \
    --lookup-attributes \
        AttributeKey=ResourceName,AttributeValue=arn:aws:s3:::source-bucket \
    | jq
```

## Getting Help

### AWS Support

```bash
# Create support case
aws support create-case \
    --subject "S3 Deep Archive restore issue" \
    --service-code "amazon-s3" \
    --severity-code "low" \
    --category-code "other" \
    --communication-body "Description of your issue..."
```

### Community Resources

- AWS Forums: https://forums.aws.amazon.com/forum.jspa?forumID=24
- Stack Overflow: https://stackoverflow.com/questions/tagged/amazon-s3
- AWS re:Post: https://repost.aws/tags/TA4KeKSFxNQmygWYi-JcZjJw/amazon-s3

### Useful AWS Documentation

- [S3 Error Codes](https://docs.aws.amazon.com/AmazonS3/latest/API/ErrorResponses.html)
- [Cross-Account Access](https://docs.aws.amazon.com/AmazonS3/latest/userguide/example-walkthroughs-managing-access-example2.html)
- [Restoring Archived Objects](https://docs.aws.amazon.com/AmazonS3/latest/userguide/restoring-objects.html)
- [S3 Storage Classes](https://docs.aws.amazon.com/AmazonS3/latest/userguide/storage-class-intro.html)

## Diagnostic Checklist

When troubleshooting, go through this checklist:

- [ ] AWS CLI installed and configured
- [ ] Correct AWS credentials/profile in use
- [ ] Source bucket exists and accessible
- [ ] Target bucket exists and accessible
- [ ] Bucket policies allow cross-account access
- [ ] IAM policies grant necessary permissions
- [ ] Objects are in expected storage class
- [ ] Objects are fully restored (if Deep Archive)
- [ ] System clock is synchronized
- [ ] Network connectivity to AWS is working
- [ ] AWS CLI is up to date
- [ ] Scripts have execute permissions
- [ ] Terraform state is not locked

## Quick Reference: Error Messages

| Error | Likely Cause | Quick Fix |
|-------|--------------|-----------|
| `AccessDenied` | IAM/bucket policy | Check permissions |
| `NoSuchBucket` | Bucket doesn't exist | Verify bucket name |
| `NoSuchKey` | Object doesn't exist | Check object path |
| `InvalidObjectState` | Not restored | Run restore first |
| `RestoreAlreadyInProgress` | Already restoring | Wait for completion |
| `RequestTimeTooSkewed` | Clock out of sync | Sync system time |
| `BucketNotEmpty` | Can't delete | Empty bucket first |
| `BucketAlreadyExists` | Name taken | Use unique name |

