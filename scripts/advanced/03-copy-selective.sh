#!/bin/bash

##############################################################################
# Script: 03-copy-selective.sh
# Purpose: Selectively copy restored data to target account
# Usage: ./03-copy-selective.sh [source-bucket] [target-bucket] [year] [type]
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

# Parameters
SOURCE_BUCKET=${1:-}
TARGET_BUCKET=${2:-}
TARGET_YEAR=${3:-2024}
TARGET_TYPE=${4:-all}

if [ -z "$SOURCE_BUCKET" ] || [ -z "$TARGET_BUCKET" ]; then
    print_error "Bucket names required"
    echo "Usage: $0 <source-bucket> <target-bucket> [year] [type]"
    echo ""
    echo "Examples:"
    echo "  $0 source-bucket target-bucket 2024"
    echo "  $0 source-bucket target-bucket 2024 backups"
    exit 1
fi

echo ""
echo "=========================================="
echo "Cross-Account Selective Copy"
echo "=========================================="
echo "Source: $SOURCE_BUCKET"
echo "Target: $TARGET_BUCKET"
echo "Year: $TARGET_YEAR"
echo "Type: $TARGET_TYPE"
echo ""

# Build prefix
if [ "$TARGET_TYPE" = "all" ]; then
    PREFIX="${TARGET_YEAR}/"
else
    PREFIX="${TARGET_YEAR}/${TARGET_TYPE}/"
fi

# Verify access
print_info "Verifying bucket access..."

if ! aws s3 ls "s3://$SOURCE_BUCKET/$PREFIX" > /dev/null 2>&1; then
    print_error "Cannot access source: s3://$SOURCE_BUCKET/$PREFIX"
    exit 1
fi
print_success "Source accessible"

if ! aws s3 ls "s3://$TARGET_BUCKET/" > /dev/null 2>&1; then
    print_error "Cannot access target: $TARGET_BUCKET"
    exit 1
fi
print_success "Target accessible"

# List objects
print_info "Listing objects to copy..."

OBJECTS=$(aws s3api list-objects-v2 \
    --bucket "$SOURCE_BUCKET" \
    --prefix "$PREFIX" \
    --query 'Contents[].Key' \
    --output text)

if [ -z "$OBJECTS" ]; then
    print_error "No objects found with prefix: $PREFIX"
    exit 1
fi

OBJECT_COUNT=$(echo "$OBJECTS" | wc -w)
print_success "Found $OBJECT_COUNT objects"

# Check restore status
print_info "Checking restore status..."

ALL_RESTORED=true
RESTORED_COUNT=0
NOT_RESTORED_COUNT=0

for KEY in $OBJECTS; do
    STATUS=$(aws s3api head-object \
        --bucket "$SOURCE_BUCKET" \
        --key "$KEY" \
        2>/dev/null)

    STORAGE_CLASS=$(echo "$STATUS" | grep -o '"StorageClass": "[^"]*"' | cut -d'"' -f4)
    RESTORE_INFO=$(echo "$STATUS" | grep '"Restore":' || echo "")

    if [ "$STORAGE_CLASS" = "DEEP_ARCHIVE" ]; then
        if [[ "$RESTORE_INFO" =~ ongoing-request=\"false\" ]]; then
            ((RESTORED_COUNT++))
        else
            ALL_RESTORED=false
            ((NOT_RESTORED_COUNT++))

            if [ $NOT_RESTORED_COUNT -le 5 ]; then
                print_warning "Not restored: $KEY"
            fi
        fi
    else
        ((RESTORED_COUNT++))
    fi
done

echo ""
echo "Restore Status:"
echo "  Restored: $RESTORED_COUNT / $OBJECT_COUNT"
echo "  Not restored: $NOT_RESTORED_COUNT / $OBJECT_COUNT"

if [ "$ALL_RESTORED" = false ]; then
    echo ""
    print_warning "Some objects are not fully restored yet"
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Copy cancelled"
        exit 0
    fi
fi

# Calculate size
print_info "Calculating data size..."

TOTAL_SIZE=0
for KEY in $OBJECTS; do
    SIZE=$(aws s3api head-object \
        --bucket "$SOURCE_BUCKET" \
        --key "$KEY" \
        --query 'ContentLength' \
        --output text 2>/dev/null || echo "0")
    TOTAL_SIZE=$((TOTAL_SIZE + SIZE))
done

SIZE_GB=$(echo "scale=2; $TOTAL_SIZE / 1073741824" | bc)

echo ""
echo "Data Summary:"
echo "  Objects: $OBJECT_COUNT"
echo "  Total Size: ${SIZE_GB} GB"
echo ""

# Confirm
read -p "Proceed with copy? (y/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_info "Copy cancelled"
    exit 0
fi

# Copy objects
print_info "Copying objects..."

SUCCESS_COUNT=0
FAILED_COUNT=0
SKIPPED_COUNT=0

START_TIME=$(date +%s)

# Progress tracking
PROGRESS_FILE="/tmp/copy-progress-${TARGET_YEAR}-${TARGET_TYPE}.txt"
> "$PROGRESS_FILE"

COUNT=0
for KEY in $OBJECTS; do
    ((COUNT++))

    # Progress
    PERCENT=$((COUNT * 100 / OBJECT_COUNT))
    echo -ne "\rProgress: $COUNT/$OBJECT_COUNT ($PERCENT%)"

    # Target key (preserve structure or flatten)
    TARGET_KEY="$KEY"  # Preserve year/type structure

    # Check if already exists in target
    if aws s3api head-object \
        --bucket "$TARGET_BUCKET" \
        --key "$TARGET_KEY" \
        > /dev/null 2>&1; then

        # Compare sizes
        SOURCE_SIZE=$(aws s3api head-object \
            --bucket "$SOURCE_BUCKET" \
            --key "$KEY" \
            --query 'ContentLength' \
            --output text)

        TARGET_SIZE=$(aws s3api head-object \
            --bucket "$TARGET_BUCKET" \
            --key "$TARGET_KEY" \
            --query 'ContentLength' \
            --output text)

        if [ "$SOURCE_SIZE" = "$TARGET_SIZE" ]; then
            echo "SKIP:$KEY" >> "$PROGRESS_FILE"
            ((SKIPPED_COUNT++))
            continue
        fi
    fi

    # Copy
    if aws s3 cp \
        "s3://$SOURCE_BUCKET/$KEY" \
        "s3://$TARGET_BUCKET/$TARGET_KEY" \
        --metadata-directive COPY \
        --quiet 2>/dev/null; then

        echo "SUCCESS:$KEY" >> "$PROGRESS_FILE"
        ((SUCCESS_COUNT++))
    else
        echo "FAILED:$KEY" >> "$PROGRESS_FILE"
        ((FAILED_COUNT++))
    fi

    # Rate limiting
    sleep 0.05
done

echo ""  # New line after progress

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# Calculate speed
if [ $DURATION -gt 0 ]; then
    SPEED_MBPS=$(echo "scale=2; $TOTAL_SIZE / $DURATION / 1048576" | bc)
else
    SPEED_MBPS="N/A"
fi

echo ""
echo "=========================================="
echo "Copy Summary"
echo "=========================================="
echo "Successful: $SUCCESS_COUNT"
echo "Failed: $FAILED_COUNT"
echo "Skipped (already exists): $SKIPPED_COUNT"
echo "Total: $OBJECT_COUNT"
echo "Duration: $DURATION seconds"
echo "Average speed: ${SPEED_MBPS} MB/s"
echo ""

# Verify
if [ $SUCCESS_COUNT -gt 0 ]; then
    print_info "Verifying copied objects..."

    VERIFIED=0
    VERIFY_FAILED=0

    # Sample verification (first 10 objects)
    SAMPLE_COUNT=0
    for KEY in $OBJECTS; do
        if [ $SAMPLE_COUNT -ge 10 ]; then
            break
        fi

        TARGET_KEY="$KEY"

        SOURCE_SIZE=$(aws s3api head-object \
            --bucket "$SOURCE_BUCKET" \
            --key "$KEY" \
            --query 'ContentLength' \
            --output text 2>/dev/null || echo "0")

        TARGET_SIZE=$(aws s3api head-object \
            --bucket "$TARGET_BUCKET" \
            --key "$TARGET_KEY" \
            --query 'ContentLength' \
            --output text 2>/dev/null || echo "0")

        if [ "$SOURCE_SIZE" = "$TARGET_SIZE" ]; then
            ((VERIFIED++))
        else
            ((VERIFY_FAILED++))
            print_warning "Size mismatch: $KEY"
        fi

        ((SAMPLE_COUNT++))
    done

    echo ""
    echo "Verification (sample of $SAMPLE_COUNT objects):"
    echo "  Verified: $VERIFIED"
    echo "  Failed: $VERIFY_FAILED"
fi

# Generate report
REPORT_FILE="/tmp/copy-report-${TARGET_YEAR}-${TARGET_TYPE}-$(date +%Y%m%d-%H%M%S).txt"
cat > "$REPORT_FILE" << EOF
Cross-Account Copy Report
=========================

Timestamp: $(date)

Source: s3://$SOURCE_BUCKET/$PREFIX
Target: s3://$TARGET_BUCKET/

Year: $TARGET_YEAR
Type: $TARGET_TYPE

Summary:
--------
Total objects: $OBJECT_COUNT
Successful: $SUCCESS_COUNT
Failed: $FAILED_COUNT
Skipped: $SKIPPED_COUNT

Size: ${SIZE_GB} GB
Duration: $DURATION seconds
Speed: ${SPEED_MBPS} MB/s

Detailed Progress:
-----------------
$(cat $PROGRESS_FILE)

EOF

print_success "Report saved: $REPORT_FILE"

echo ""
echo "=========================================="
echo "Next Steps"
echo "=========================================="
echo ""

if [ $FAILED_COUNT -gt 0 ]; then
    print_warning "Some files failed to copy"
    echo "  1. Review failed files:"
    echo "     grep FAILED $PROGRESS_FILE"
    echo ""
    echo "  2. Retry failed files:"
    echo "     ./03-copy-selective.sh $SOURCE_BUCKET $TARGET_BUCKET $TARGET_YEAR $TARGET_TYPE"
    echo ""
fi

if [ $SUCCESS_COUNT -gt 0 ]; then
    print_success "Copy completed successfully!"
    echo ""
    echo "  1. Verify in target:"
    echo "     aws s3 ls s3://$TARGET_BUCKET/$PREFIX --recursive --human-readable"
    echo ""
    echo "  2. Copy other years/types if needed:"
    echo "     ./03-copy-selective.sh $SOURCE_BUCKET $TARGET_BUCKET 2023"
    echo ""
fi

print_info "Full report: $REPORT_FILE"
