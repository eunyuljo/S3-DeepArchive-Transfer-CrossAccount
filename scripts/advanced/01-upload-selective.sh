#!/bin/bash

##############################################################################
# Script: 01-upload-selective.sh
# Purpose: Selectively upload year-based data to Deep Archive
# Usage: ./01-upload-selective.sh [bucket] [year|all] [type]
#        year: 2022, 2023, 2024, 2025, all
#        type: backups, logs, reports, all (default: all)
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
TARGET_YEAR=${2:-all}
TARGET_TYPE=${3:-all}

if [ -z "$SOURCE_BUCKET" ]; then
    if [ -f "/tmp/source-bucket-name.txt" ]; then
        SOURCE_BUCKET=$(cat /tmp/source-bucket-name.txt)
    else
        print_error "Bucket name required"
        echo "Usage: $0 <bucket> [year|all] [type|all]"
        echo "  year: 2022, 2023, 2024, 2025, all"
        echo "  type: backups, logs, reports, all"
        echo ""
        echo "Examples:"
        echo "  $0 my-bucket 2024           # Upload all 2024 data"
        echo "  $0 my-bucket 2024 backups   # Upload only 2024 backups"
        echo "  $0 my-bucket all            # Upload all years"
        exit 1
    fi
fi

TEST_DIR="../test-data/realistic"

if [ ! -d "$TEST_DIR" ]; then
    print_error "Test data not found. Run 00-create-realistic-test-data.sh first"
    exit 1
fi

echo ""
echo "=========================================="
echo "Selective Upload to Deep Archive"
echo "=========================================="
echo "Bucket: $SOURCE_BUCKET"
echo "Year filter: $TARGET_YEAR"
echo "Type filter: $TARGET_TYPE"
echo ""

# Determine years to upload
if [ "$TARGET_YEAR" = "all" ]; then
    YEARS=(2022 2023 2024 2025)
else
    YEARS=($TARGET_YEAR)
fi

# Determine types to upload
if [ "$TARGET_TYPE" = "all" ]; then
    TYPES=(backups logs reports)
else
    TYPES=($TARGET_TYPE)
fi

print_info "Will upload years: ${YEARS[@]}"
print_info "Will upload types: ${TYPES[@]}"
echo ""

# Confirm
read -p "Proceed with upload? (y/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_info "Upload cancelled"
    exit 0
fi

# Upload
UPLOADED_FILES=0
FAILED_FILES=0
TOTAL_SIZE=0

START_TIME=$(date +%s)

for YEAR in "${YEARS[@]}"; do
    for TYPE in "${TYPES[@]}"; do
        SOURCE_DIR="$TEST_DIR/$YEAR/$TYPE"

        if [ ! -d "$SOURCE_DIR" ]; then
            print_warning "Directory not found: $SOURCE_DIR (skipping)"
            continue
        fi

        print_info "Uploading $YEAR/$TYPE..."

        # Find all .dat files
        FILES=$(find "$SOURCE_DIR" -type f -name "*.dat")
        FILE_COUNT=$(echo "$FILES" | wc -l)

        if [ -z "$FILES" ] || [ "$FILE_COUNT" -eq 0 ]; then
            print_warning "No files in $YEAR/$TYPE"
            continue
        fi

        print_info "  Found $FILE_COUNT files"

        # Upload each file
        BATCH_SUCCESS=0
        BATCH_FAILED=0

        echo "$FILES" | while read FILE; do
            if [ -z "$FILE" ]; then
                continue
            fi

            # Determine S3 key
            REL_PATH=$(echo $FILE | sed "s|$TEST_DIR/||")
            S3_KEY="$REL_PATH"

            # Upload
            if aws s3 cp "$FILE" "s3://$SOURCE_BUCKET/$S3_KEY" \
                --storage-class DEEP_ARCHIVE \
                --metadata year=$YEAR,type=$TYPE \
                --quiet 2>/dev/null; then

                # Also upload metadata file if exists
                if [ -f "${FILE}.meta" ]; then
                    aws s3 cp "${FILE}.meta" "s3://$SOURCE_BUCKET/${S3_KEY}.meta" \
                        --storage-class DEEP_ARCHIVE \
                        --quiet 2>/dev/null || true
                fi

                echo "✓ $(basename $FILE)"
            else
                echo "✗ $(basename $FILE)" >&2
            fi
        done

        # Count uploaded files
        UPLOADED=$(aws s3 ls "s3://$SOURCE_BUCKET/$YEAR/$TYPE/" --recursive | wc -l)
        print_success "  Uploaded: $UPLOADED files"

        ((UPLOADED_FILES += UPLOADED))
    done
done

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo ""
echo "=========================================="
echo "Upload Summary"
echo "=========================================="
echo "Total files uploaded: $UPLOADED_FILES"
echo "Duration: $DURATION seconds"
echo ""

# Verify uploads
print_info "Verifying uploads..."
echo ""

for YEAR in "${YEARS[@]}"; do
    for TYPE in "${TYPES[@]}"; do
        COUNT=$(aws s3 ls "s3://$SOURCE_BUCKET/$YEAR/$TYPE/" --recursive 2>/dev/null | wc -l)

        if [ $COUNT -gt 0 ]; then
            SIZE=$(aws s3 ls "s3://$SOURCE_BUCKET/$YEAR/$TYPE/" --recursive --human-readable --summarize 2>/dev/null | grep "Total Size" | awk '{print $3" "$4}')
            print_success "$YEAR/$TYPE: $COUNT files, $SIZE"
        fi
    done
done

echo ""
echo "=========================================="
echo "Next Steps"
echo "=========================================="
echo ""
echo "1. Verify storage class:"
echo "   aws s3api head-object --bucket $SOURCE_BUCKET --key 2024/backups/backups_2024_0001.dat"
echo ""
echo "2. Restore specific year:"
echo "   ./02-restore-selective.sh $SOURCE_BUCKET 2024"
echo ""
echo "3. Or restore specific type:"
echo "   ./02-restore-selective.sh $SOURCE_BUCKET 2024 backups"
echo ""

# Save upload info
cat > /tmp/upload-info.txt << EOF
SOURCE_BUCKET=$SOURCE_BUCKET
UPLOADED_YEARS="${YEARS[@]}"
UPLOADED_TYPES="${TYPES[@]}"
UPLOAD_TIME=$(date +%Y-%m-%d_%H:%M:%S)
UPLOADED_FILES=$UPLOADED_FILES
EOF

print_success "Upload complete!"
