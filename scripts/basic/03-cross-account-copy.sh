#!/bin/bash

##############################################################################
# Script: 03-cross-account-copy.sh
# Purpose: Copy restored objects from source to target bucket (cross-account)
# Usage: ./03-cross-account-copy.sh [source-bucket] [target-bucket]
##############################################################################

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

print_header() {
    echo ""
    echo "=========================================="
    echo "$1"
    echo "=========================================="
    echo ""
}

# Check AWS CLI
if ! command -v aws &> /dev/null; then
    print_error "AWS CLI is not installed."
    exit 1
fi

# Get parameters
SOURCE_BUCKET=${1:-}
TARGET_BUCKET=${2:-}

# Try to get from saved info
if [ -z "$SOURCE_BUCKET" ] && [ -f "/tmp/source-bucket-name.txt" ]; then
    SOURCE_BUCKET=$(cat /tmp/source-bucket-name.txt)
fi

if [ -z "$TARGET_BUCKET" ]; then
    # Try to get from terraform output
    if [ -d "../target-account" ]; then
        cd ../target-account
        TARGET_BUCKET=$(terraform output -raw target_bucket_name 2>/dev/null || echo "")
        cd - > /dev/null
    fi
fi

if [ -z "$SOURCE_BUCKET" ] || [ -z "$TARGET_BUCKET" ]; then
    print_error "Both source and target bucket names are required."
    echo "Usage: $0 <source-bucket> <target-bucket>"
    exit 1
fi

print_header "S3 Cross-Account Copy"
print_info "Source Bucket: $SOURCE_BUCKET"
print_info "Target Bucket: $TARGET_BUCKET"

# Verify access to both buckets
print_info "Verifying bucket access..."

if ! aws s3 ls "s3://${SOURCE_BUCKET}/" > /dev/null 2>&1; then
    print_error "Cannot access source bucket: $SOURCE_BUCKET"
    print_info "Check your AWS credentials and bucket policy"
    exit 1
fi
print_success "Source bucket accessible"

if ! aws s3 ls "s3://${TARGET_BUCKET}/" > /dev/null 2>&1; then
    print_error "Cannot access target bucket: $TARGET_BUCKET"
    print_info "Check your AWS credentials and IAM permissions"
    exit 1
fi
print_success "Target bucket accessible"

# List objects to copy
print_info "Listing restored objects..."

OBJECTS=$(aws s3api list-objects-v2 \
    --bucket "$SOURCE_BUCKET" \
    --prefix "deep-archive/" \
    --query 'Contents[].Key' \
    --output text)

if [ -z "$OBJECTS" ]; then
    print_error "No objects found in deep-archive/ prefix"
    exit 1
fi

OBJECT_COUNT=$(echo "$OBJECTS" | wc -w)
print_success "Found $OBJECT_COUNT objects to copy"

# Check restore status
print_header "Checking Restore Status"

ALL_RESTORED=true
for key in $OBJECTS; do
    print_info "Checking: $key"

    RESTORE_STATUS=$(aws s3api head-object \
        --bucket "$SOURCE_BUCKET" \
        --key "$key" \
        2>/dev/null)

    STORAGE_CLASS=$(echo "$RESTORE_STATUS" | grep -o '"StorageClass": "[^"]*"' | cut -d'"' -f4)
    RESTORE_INFO=$(echo "$RESTORE_STATUS" | grep '"Restore":' || echo "")

    if [ "$STORAGE_CLASS" = "DEEP_ARCHIVE" ]; then
        if [[ "$RESTORE_INFO" =~ ongoing-request=\"false\" ]]; then
            print_success "✓ Restored: $key"
        elif [[ "$RESTORE_INFO" =~ ongoing-request=\"true\" ]]; then
            print_warning "⟳ Restore in progress: $key"
            ALL_RESTORED=false
        else
            print_error "✗ Not restored: $key"
            ALL_RESTORED=false
        fi
    else
        print_success "✓ Available (${STORAGE_CLASS}): $key"
    fi
done

if [ "$ALL_RESTORED" = false ]; then
    echo ""
    print_warning "Some objects are not fully restored yet."
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Copy cancelled. Wait for restore to complete."
        exit 0
    fi
fi

# Estimate data size
print_header "Calculating Data Size"

TOTAL_SIZE=0
for key in $OBJECTS; do
    SIZE=$(aws s3api head-object \
        --bucket "$SOURCE_BUCKET" \
        --key "$key" \
        --query 'ContentLength' \
        --output text 2>/dev/null || echo "0")

    TOTAL_SIZE=$((TOTAL_SIZE + SIZE))
done

# Convert bytes to human readable
if [ $TOTAL_SIZE -lt 1024 ]; then
    SIZE_HR="${TOTAL_SIZE} B"
elif [ $TOTAL_SIZE -lt 1048576 ]; then
    SIZE_HR="$(echo "scale=2; $TOTAL_SIZE / 1024" | bc) KB"
elif [ $TOTAL_SIZE -lt 1073741824 ]; then
    SIZE_HR="$(echo "scale=2; $TOTAL_SIZE / 1048576" | bc) MB"
else
    SIZE_HR="$(echo "scale=2; $TOTAL_SIZE / 1073741824" | bc) GB"
fi

print_info "Total data size: $SIZE_HR ($TOTAL_SIZE bytes)"

# Estimate cost (rough)
TRANSFER_COST=0
GB_SIZE=$(echo "scale=4; $TOTAL_SIZE / 1073741824" | bc)
if (( $(echo "$GB_SIZE > 0" | bc -l) )); then
    print_info "Estimated size: ${GB_SIZE} GB"
fi

# Confirm copy
echo ""
print_warning "This will copy $OBJECT_COUNT objects ($SIZE_HR) from:"
echo "  Source: s3://$SOURCE_BUCKET/deep-archive/"
echo "  Target: s3://$TARGET_BUCKET/restored/"
echo ""
read -p "Proceed with copy? (y/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_info "Copy cancelled"
    exit 0
fi

# Perform copy
print_header "Copying Objects"

SUCCESS_COUNT=0
FAILED_COUNT=0
START_TIME=$(date +%s)

for key in $OBJECTS; do
    filename=$(basename "$key")
    target_key="restored/$filename"

    print_info "Copying: $key → $target_key"

    if aws s3 cp \
        "s3://${SOURCE_BUCKET}/${key}" \
        "s3://${TARGET_BUCKET}/${target_key}" \
        --metadata-directive COPY 2>/dev/null; then

        print_success "✓ Copied: $filename"
        ((SUCCESS_COUNT++))
    else
        print_error "✗ Failed: $filename"
        ((FAILED_COUNT++))

        # Check error
        ERROR=$(aws s3 cp \
            "s3://${SOURCE_BUCKET}/${key}" \
            "s3://${TARGET_BUCKET}/${target_key}" 2>&1 || true)

        if [[ "$ERROR" =~ "InvalidObjectState" ]]; then
            print_warning "  Object not restored yet"
        elif [[ "$ERROR" =~ "AccessDenied" ]]; then
            print_error "  Access denied - check bucket policy and IAM permissions"
        fi
    fi
done

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# Copy summary
print_header "Copy Summary"
echo "Successfully copied: ${SUCCESS_COUNT}"
echo "Failed: ${FAILED_COUNT}"
echo "Duration: ${DURATION} seconds"
echo ""

# Verify copied objects
if [ $SUCCESS_COUNT -gt 0 ]; then
    print_header "Verifying Copied Objects"

    print_info "Listing objects in target bucket..."
    aws s3 ls "s3://${TARGET_BUCKET}/restored/" --recursive --human-readable

    # Verify checksums if available
    CHECKSUM_FILE="../test-data/sample-files/checksums.txt"
    if [ -f "$CHECKSUM_FILE" ]; then
        print_info "Checksum file found. Verifying integrity..."

        VERIFY_DIR="/tmp/verify-copy"
        mkdir -p "$VERIFY_DIR"

        for key in $OBJECTS; do
            filename=$(basename "$key")

            # Download from target
            if aws s3 cp "s3://${TARGET_BUCKET}/restored/${filename}" \
                "${VERIFY_DIR}/${filename}" > /dev/null 2>&1; then

                # Calculate checksums
                MD5=$(md5sum "${VERIFY_DIR}/${filename}" | awk '{print $1}')

                # Compare with original
                ORIGINAL_MD5=$(grep -A 1 "File: ${filename}" "$CHECKSUM_FILE" | grep "MD5:" | awk '{print $2}')

                if [ "$MD5" = "$ORIGINAL_MD5" ]; then
                    print_success "✓ Integrity verified: $filename"
                else
                    print_error "✗ Integrity check failed: $filename"
                    echo "  Expected: $ORIGINAL_MD5"
                    echo "  Got: $MD5"
                fi
            fi
        done

        # Cleanup
        rm -rf "$VERIFY_DIR"
    else
        print_warning "No checksum file found. Skipping integrity check."
    fi
fi

# Generate report
REPORT_FILE="/tmp/copy-report-$(date +%Y%m%d-%H%M%S).txt"
cat > "$REPORT_FILE" << EOF
S3 Cross-Account Copy Report
============================

Timestamp: $(date)
Source Bucket: $SOURCE_BUCKET
Target Bucket: $TARGET_BUCKET

Objects copied: $SUCCESS_COUNT
Failed: $FAILED_COUNT
Total size: $SIZE_HR
Duration: $DURATION seconds

Source: s3://$SOURCE_BUCKET/deep-archive/
Target: s3://$TARGET_BUCKET/restored/

Objects:
$(echo "$OBJECTS" | tr ' ' '\n')

Status: $([ $FAILED_COUNT -eq 0 ] && echo "SUCCESS" || echo "PARTIAL")
EOF

print_success "Report saved to: $REPORT_FILE"

# Next steps
print_header "Next Steps"

if [ $FAILED_COUNT -eq 0 ]; then
    print_success "All objects copied successfully!"
    echo ""
    echo "You can now:"
    echo "1. Verify data in target bucket:"
    echo "   aws s3 ls s3://$TARGET_BUCKET/restored/ --recursive"
    echo ""
    echo "2. Download and verify locally:"
    echo "   aws s3 sync s3://$TARGET_BUCKET/restored/ ./downloaded/"
    echo ""
    echo "3. Clean up (optional):"
    echo "   ./04-cleanup.sh"
else
    print_warning "Some objects failed to copy."
    echo "Review errors above and:"
    echo "1. Check bucket policies"
    echo "2. Verify IAM permissions"
    echo "3. Ensure objects are fully restored"
    echo "4. Re-run this script to retry"
fi

print_success "Copy operation completed!"
