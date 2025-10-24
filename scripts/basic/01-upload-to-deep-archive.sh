#!/bin/bash

##############################################################################
# Script: 01-upload-to-deep-archive.sh
# Purpose: Upload test files to S3 with Deep Archive storage class
# Usage: ./01-upload-to-deep-archive.sh [source-bucket-name]
##############################################################################

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored messages
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo ""
    echo "=========================================="
    echo "$1"
    echo "=========================================="
    echo ""
}

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    print_error "AWS CLI is not installed. Please install it first."
    exit 1
fi

# Get source bucket name
SOURCE_BUCKET=${1:-}

if [ -z "$SOURCE_BUCKET" ]; then
    print_warning "No bucket name provided. Checking terraform output..."

    # Try to get from terraform output
    if [ -d "../source-account" ]; then
        cd ../source-account
        SOURCE_BUCKET=$(terraform output -raw source_bucket_name 2>/dev/null || echo "")
        cd - > /dev/null
    fi

    if [ -z "$SOURCE_BUCKET" ]; then
        print_error "Could not determine source bucket name."
        echo "Usage: $0 <source-bucket-name>"
        exit 1
    fi
fi

print_header "S3 Deep Archive Upload Test"
print_info "Source Bucket: $SOURCE_BUCKET"

# Check if bucket exists
print_info "Checking if bucket exists..."
if ! aws s3 ls "s3://${SOURCE_BUCKET}" > /dev/null 2>&1; then
    print_error "Bucket ${SOURCE_BUCKET} does not exist or you don't have access."
    exit 1
fi
print_success "Bucket exists and accessible"

# Create test data directory
TEST_DATA_DIR="../test-data/sample-files"
mkdir -p "$TEST_DATA_DIR"

print_info "Creating test files..."

# Create various test files
cat > "${TEST_DATA_DIR}/test-small.txt" << EOF
This is a small test file for S3 Deep Archive testing.
Created at: $(date)
EOF

# Create medium size file (1MB)
dd if=/dev/urandom of="${TEST_DATA_DIR}/test-medium.bin" bs=1M count=1 2>/dev/null
print_success "Created 1MB test file"

# Create larger file (10MB)
dd if=/dev/urandom of="${TEST_DATA_DIR}/test-large.bin" bs=1M count=10 2>/dev/null
print_success "Created 10MB test file"

# Create JSON test file
cat > "${TEST_DATA_DIR}/test-data.json" << EOF
{
  "test_id": "deep-archive-test-001",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "purpose": "S3 Deep Archive cross-account transfer test",
  "files": [
    "test-small.txt",
    "test-medium.bin",
    "test-large.bin"
  ]
}
EOF

# Create CSV test file
cat > "${TEST_DATA_DIR}/test-data.csv" << EOF
id,name,value,timestamp
1,Test1,100,$(date +%Y-%m-%d)
2,Test2,200,$(date +%Y-%m-%d)
3,Test3,300,$(date +%Y-%m-%d)
EOF

print_success "Test files created in ${TEST_DATA_DIR}"

# Upload files to S3 with DEEP_ARCHIVE storage class
print_header "Uploading to S3 Deep Archive"

FILES=(
    "test-small.txt"
    "test-medium.bin"
    "test-large.bin"
    "test-data.json"
    "test-data.csv"
)

UPLOAD_COUNT=0
FAILED_COUNT=0

for file in "${FILES[@]}"; do
    print_info "Uploading ${file}..."

    if aws s3 cp "${TEST_DATA_DIR}/${file}" \
        "s3://${SOURCE_BUCKET}/deep-archive/${file}" \
        --storage-class DEEP_ARCHIVE \
        --metadata "upload-date=$(date +%Y-%m-%d),purpose=test"; then

        print_success "Uploaded: ${file}"
        ((UPLOAD_COUNT++))
    else
        print_error "Failed to upload: ${file}"
        ((FAILED_COUNT++))
    fi
done

# Upload to standard prefix (for comparison)
print_info "Uploading one file to standard storage for comparison..."
aws s3 cp "${TEST_DATA_DIR}/test-small.txt" \
    "s3://${SOURCE_BUCKET}/standard/test-small.txt" \
    --storage-class STANDARD

# Generate file checksums
print_header "Generating Checksums"

CHECKSUM_FILE="${TEST_DATA_DIR}/checksums.txt"
> "$CHECKSUM_FILE"  # Clear file

for file in "${FILES[@]}"; do
    if [ -f "${TEST_DATA_DIR}/${file}" ]; then
        MD5=$(md5sum "${TEST_DATA_DIR}/${file}" | awk '{print $1}')
        SHA256=$(sha256sum "${TEST_DATA_DIR}/${file}" | awk '{print $1}')
        SIZE=$(stat -f%z "${TEST_DATA_DIR}/${file}" 2>/dev/null || stat -c%s "${TEST_DATA_DIR}/${file}")

        echo "File: ${file}" >> "$CHECKSUM_FILE"
        echo "  MD5:    ${MD5}" >> "$CHECKSUM_FILE"
        echo "  SHA256: ${SHA256}" >> "$CHECKSUM_FILE"
        echo "  Size:   ${SIZE} bytes" >> "$CHECKSUM_FILE"
        echo "" >> "$CHECKSUM_FILE"
    fi
done

print_success "Checksums saved to ${CHECKSUM_FILE}"

# Verify uploads
print_header "Verifying Uploads"

for file in "${FILES[@]}"; do
    print_info "Verifying ${file}..."

    # Get object metadata
    METADATA=$(aws s3api head-object \
        --bucket "${SOURCE_BUCKET}" \
        --key "deep-archive/${file}" \
        2>/dev/null || echo "")

    if [ -n "$METADATA" ]; then
        STORAGE_CLASS=$(echo "$METADATA" | grep -o '"StorageClass": "[^"]*"' | cut -d'"' -f4)
        SIZE=$(echo "$METADATA" | grep -o '"ContentLength": [0-9]*' | awk '{print $2}')

        if [ "$STORAGE_CLASS" = "DEEP_ARCHIVE" ]; then
            print_success "${file} - Storage Class: DEEP_ARCHIVE, Size: ${SIZE} bytes"
        else
            print_warning "${file} - Storage Class: ${STORAGE_CLASS} (not DEEP_ARCHIVE yet, may be transitioning)"
        fi
    else
        print_error "Could not verify ${file}"
    fi
done

# Summary
print_header "Upload Summary"
echo "Total files uploaded: ${UPLOAD_COUNT}"
echo "Failed uploads: ${FAILED_COUNT}"
echo "Source bucket: ${SOURCE_BUCKET}"
echo "S3 Path: s3://${SOURCE_BUCKET}/deep-archive/"
echo ""

# List uploaded files
print_info "Files in Deep Archive:"
aws s3 ls "s3://${SOURCE_BUCKET}/deep-archive/" --recursive --human-readable

print_header "Next Steps"
echo "1. Files are now in DEEP_ARCHIVE storage class"
echo "2. Wait for storage class transition (if not immediate)"
echo "3. Run restore script: ./02-restore-from-deep-archive.sh ${SOURCE_BUCKET}"
echo "4. Note: Restoration will take approximately 12 hours"
echo ""

print_info "Checksum file location: ${CHECKSUM_FILE}"
print_info "Keep this file to verify data integrity after transfer"

# Save bucket info for next scripts
echo "${SOURCE_BUCKET}" > /tmp/source-bucket-name.txt

print_success "Upload complete!"
