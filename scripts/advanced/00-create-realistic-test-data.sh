#!/bin/bash

##############################################################################
# Script: 00-create-realistic-test-data.sh
# Purpose: Create realistic year-based test data structure
# Usage: ./00-create-realistic-test-data.sh [bucket-name] [size-mode]
#        size-mode: small (MB), medium (GB), large (GB-realistic)
##############################################################################

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

# Parameters
SOURCE_BUCKET=${1:-}
SIZE_MODE=${2:-small}  # small, medium, large

if [ -z "$SOURCE_BUCKET" ]; then
    if [ -f "/tmp/source-bucket-name.txt" ]; then
        SOURCE_BUCKET=$(cat /tmp/source-bucket-name.txt)
    else
        echo "Usage: $0 <source-bucket-name> [size-mode]"
        echo "  size-mode: small (MB), medium (GB), large (GB-realistic)"
        exit 1
    fi
fi

print_info "Creating realistic year-based test data"
print_info "Bucket: $SOURCE_BUCKET"
print_info "Size mode: $SIZE_MODE"

# Test data directory
TEST_DIR="../test-data/realistic"
mkdir -p "$TEST_DIR"

# Size configuration
case $SIZE_MODE in
    small)
        # For quick testing (총 ~100MB)
        BACKUP_SIZE=("5M" "3M" "2M" "1M")     # 2022-2025
        LOG_SIZE=("2M" "3M" "5M" "1M")
        REPORT_SIZE=("1M" "1M" "2M" "500K")
        FILES_PER_TYPE=5
        ;;
    medium)
        # For realistic testing (총 ~10GB)
        BACKUP_SIZE=("500M" "800M" "1200M" "300M")
        LOG_SIZE=("100M" "200M" "350M" "80M")
        REPORT_SIZE=("50M" "80M" "120M" "30M")
        FILES_PER_TYPE=20
        ;;
    large)
        # For production-like testing (총 ~100GB)
        BACKUP_SIZE=("5G" "8G" "12G" "3G")
        LOG_SIZE=("1G" "2G" "3500M" "800M")
        REPORT_SIZE=("500M" "800M" "1200M" "300M")
        FILES_PER_TYPE=50
        ;;
    *)
        print_warning "Unknown size mode. Using 'small'"
        SIZE_MODE=small
        BACKUP_SIZE=("5M" "3M" "2M" "1M")
        LOG_SIZE=("2M" "3M" "5M" "1M")
        REPORT_SIZE=("1M" "1M" "2M" "500K")
        FILES_PER_TYPE=5
        ;;
esac

YEARS=(2022 2023 2024 2025)
TYPES=(backups logs reports)

echo ""
echo "=========================================="
echo "Test Data Configuration"
echo "=========================================="
echo "Years: ${YEARS[@]}"
echo "Types: ${TYPES[@]}"
echo "Files per type: $FILES_PER_TYPE"
echo ""

# Create directory structure and files
TOTAL_FILES=0
TOTAL_SIZE=0

for i in "${!YEARS[@]}"; do
    YEAR=${YEARS[$i]}

    echo "Creating $YEAR data..."

    for TYPE in "${TYPES[@]}"; do
        DIR="$TEST_DIR/$YEAR/$TYPE"
        mkdir -p "$DIR"

        # Get size for this year/type
        case $TYPE in
            backups) SIZE=${BACKUP_SIZE[$i]} ;;
            logs) SIZE=${LOG_SIZE[$i]} ;;
            reports) SIZE=${REPORT_SIZE[$i]} ;;
        esac

        # Calculate size per file
        SIZE_NUM=$(echo $SIZE | sed 's/[^0-9]//g')
        SIZE_UNIT=$(echo $SIZE | sed 's/[0-9]//g')

        case $SIZE_UNIT in
            K|k) MULTIPLIER=1 ;;
            M|m) MULTIPLIER=1024 ;;
            G|g) MULTIPLIER=$((1024*1024)) ;;
            *) MULTIPLIER=1 ;;
        esac

        TOTAL_KB=$((SIZE_NUM * MULTIPLIER))
        PER_FILE_KB=$((TOTAL_KB / FILES_PER_TYPE))

        # Create files
        for j in $(seq 1 $FILES_PER_TYPE); do
            FILENAME="$DIR/${TYPE}_${YEAR}_$(printf "%04d" $j).dat"

            # Create file with random data (using /dev/zero for speed)
            dd if=/dev/zero of="$FILENAME" bs=1024 count=$PER_FILE_KB 2>/dev/null
            echo "  Created: $YEAR/$TYPE file $j/$FILES_PER_TYPE"

            # Add metadata file for some files
            if [ $((j % 5)) -eq 0 ]; then
                cat > "${FILENAME}.meta" << EOF
{
  "year": $YEAR,
  "type": "$TYPE",
  "file_number": $j,
  "created": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "checksum": "$(md5sum $FILENAME | awk '{print $1}')"
}
EOF
            fi

            ((TOTAL_FILES++))
        done

        TOTAL_SIZE=$((TOTAL_SIZE + TOTAL_KB))

        print_success "  $YEAR/$TYPE: $FILES_PER_TYPE files ($SIZE)"
    done
done

echo ""
echo "=========================================="
echo "Summary"
echo "=========================================="
echo "Total files: $TOTAL_FILES"
echo "Total size: $((TOTAL_SIZE / 1024)) MB"
echo ""

# Generate upload manifest
MANIFEST="$TEST_DIR/upload-manifest.txt"
echo "# Upload Manifest - Generated $(date)" > "$MANIFEST"
echo "# Bucket: $SOURCE_BUCKET" >> "$MANIFEST"
echo "# Size mode: $SIZE_MODE" >> "$MANIFEST"
echo "" >> "$MANIFEST"

find "$TEST_DIR" -type f -name "*.dat" | sort | while read file; do
    REL_PATH=$(echo $file | sed "s|$TEST_DIR/||")
    echo "$REL_PATH" >> "$MANIFEST"
done

print_success "Manifest created: $MANIFEST"

# Generate summary by year
SUMMARY="$TEST_DIR/summary.txt"
cat > "$SUMMARY" << 'EOF'
Test Data Summary
=================

Directory Structure:
EOF

tree "$TEST_DIR" -L 2 >> "$SUMMARY" 2>/dev/null || find "$TEST_DIR" -type d >> "$SUMMARY"

echo "" >> "$SUMMARY"
echo "File Count by Year/Type:" >> "$SUMMARY"
for YEAR in "${YEARS[@]}"; do
    echo "" >> "$SUMMARY"
    echo "$YEAR:" >> "$SUMMARY"
    for TYPE in "${TYPES[@]}"; do
        COUNT=$(find "$TEST_DIR/$YEAR/$TYPE" -type f -name "*.dat" 2>/dev/null | wc -l)
        SIZE=$(du -sh "$TEST_DIR/$YEAR/$TYPE" 2>/dev/null | awk '{print $1}')
        echo "  $TYPE: $COUNT files, $SIZE" >> "$SUMMARY"
    done
done

print_success "Summary created: $SUMMARY"

echo ""
echo "=========================================="
echo "Next Steps"
echo "=========================================="
echo ""
echo "1. Review generated data:"
echo "   cat $SUMMARY"
echo ""
echo "2. Upload specific year (recommended):"
echo "   ./01-upload-selective.sh $SOURCE_BUCKET 2024"
echo ""
echo "3. Or upload all years:"
echo "   ./01-upload-selective.sh $SOURCE_BUCKET all"
echo ""
echo "Data location: $TEST_DIR"
echo ""

# Save bucket name
echo "$SOURCE_BUCKET" > /tmp/source-bucket-name.txt

print_success "Test data generation complete!"
