#!/bin/bash

##############################################################################
# Script: 02-restore-selective.sh
# Purpose: Selectively restore year-based Deep Archive data
# Usage: ./02-restore-selective.sh [bucket] [year] [type] [tier] [days]
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
TARGET_YEAR=${2:-2024}       # Default to most recent year
TARGET_TYPE=${3:-all}        # backups, logs, reports, all
RESTORE_TIER=${4:-Bulk}      # Bulk or Standard
RESTORE_DAYS=${5:-7}         # Days to keep restored data

if [ -z "$SOURCE_BUCKET" ]; then
    if [ -f "/tmp/source-bucket-name.txt" ]; then
        SOURCE_BUCKET=$(cat /tmp/source-bucket-name.txt)
    else
        print_error "Bucket name required"
        echo "Usage: $0 <bucket> [year] [type] [tier] [days]"
        echo ""
        echo "Examples:"
        echo "  $0 my-bucket 2024              # Restore all 2024 data"
        echo "  $0 my-bucket 2024 backups      # Restore only 2024 backups"
        echo "  $0 my-bucket 2024 all Bulk 7   # Full parameters"
        exit 1
    fi
fi

echo ""
echo "=========================================="
echo "Selective Deep Archive Restore"
echo "=========================================="
echo "Bucket: $SOURCE_BUCKET"
echo "Year: $TARGET_YEAR"
echo "Type: $TARGET_TYPE"
echo "Restore Tier: $RESTORE_TIER (12 hours)"
echo "Restore Days: $RESTORE_DAYS"
echo ""

# Build prefix
if [ "$TARGET_TYPE" = "all" ]; then
    PREFIX="${TARGET_YEAR}/"
    print_info "Will restore all types for year $TARGET_YEAR"
else
    PREFIX="${TARGET_YEAR}/${TARGET_TYPE}/"
    print_info "Will restore only $TARGET_TYPE for year $TARGET_YEAR"
fi

# List objects
print_info "Listing objects with prefix: $PREFIX"

OBJECTS=$(aws s3api list-objects-v2 \
    --bucket "$SOURCE_BUCKET" \
    --prefix "$PREFIX" \
    --query 'Contents[?StorageClass==`DEEP_ARCHIVE`].Key' \
    --output text)

if [ -z "$OBJECTS" ]; then
    print_error "No Deep Archive objects found with prefix: $PREFIX"
    exit 1
fi

OBJECT_COUNT=$(echo "$OBJECTS" | wc -w)
print_success "Found $OBJECT_COUNT Deep Archive objects"

# Calculate estimated size and cost
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

# Calculate cost
if [ "$RESTORE_TIER" = "Bulk" ]; then
    COST=$(echo "scale=2; $SIZE_GB * 0.025" | bc)
else
    COST=$(echo "scale=2; $SIZE_GB * 0.10" | bc)
fi

echo "  Estimated Cost: \$$COST (${RESTORE_TIER} tier)"
echo ""

# Confirm
print_warning "This will initiate restore for $OBJECT_COUNT objects"
print_warning "Restore will take approximately 12 hours"
echo ""
read -p "Proceed with restore? (y/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_info "Restore cancelled"
    exit 0
fi

# Restore objects
print_info "Initiating restore requests..."

RESTORE_SUCCESS=0
RESTORE_FAILED=0
ALREADY_RESTORED=0

RESTORE_REQUEST="{\"Days\":${RESTORE_DAYS},\"GlacierJobParameters\":{\"Tier\":\"${RESTORE_TIER}\"}}"

for KEY in $OBJECTS; do
    # Check current restore status
    STATUS=$(aws s3api head-object \
        --bucket "$SOURCE_BUCKET" \
        --key "$KEY" \
        2>/dev/null | grep '"Restore":' || echo "")

    if [[ "$STATUS" =~ ongoing-request=\"false\" ]]; then
        print_warning "Already restored: $KEY"
        ((ALREADY_RESTORED++))
        continue
    fi

    if [[ "$STATUS" =~ ongoing-request=\"true\" ]]; then
        print_warning "Restore in progress: $KEY"
        ((ALREADY_RESTORED++))
        continue
    fi

    # Initiate restore
    if aws s3api restore-object \
        --bucket "$SOURCE_BUCKET" \
        --key "$KEY" \
        --restore-request "$RESTORE_REQUEST" 2>/dev/null; then

        echo "✓ $KEY"
        ((RESTORE_SUCCESS++))
    else
        ERROR_CODE=$?
        if [ $ERROR_CODE -eq 254 ]; then
            print_warning "Already restoring: $KEY"
            ((ALREADY_RESTORED++))
        else
            echo "✗ $KEY"
            ((RESTORE_FAILED++))
        fi
    fi

    # Rate limiting
    sleep 0.1
done

echo ""
echo "=========================================="
echo "Restore Summary"
echo "=========================================="
echo "New restores: $RESTORE_SUCCESS"
echo "Already restoring: $ALREADY_RESTORED"
echo "Failed: $RESTORE_FAILED"
echo "Total objects: $OBJECT_COUNT"
echo ""

if [ $RESTORE_SUCCESS -gt 0 ] || [ $ALREADY_RESTORED -gt 0 ]; then
    print_info "Restoration Details:"
    echo "  Tier: $RESTORE_TIER"
    echo "  ETA: ~12 hours"
    echo "  Available for: $RESTORE_DAYS days"
    echo "  Cost: \$$COST"
fi

# Create monitoring script
MONITOR_SCRIPT="/tmp/monitor-restore-${TARGET_YEAR}-${TARGET_TYPE}.sh"
cat > "$MONITOR_SCRIPT" << EOFMON
#!/bin/bash

SOURCE_BUCKET="$SOURCE_BUCKET"
PREFIX="$PREFIX"

echo "=========================================="
echo "Restore Status: $TARGET_YEAR/$TARGET_TYPE"
echo "=========================================="
echo ""

COMPLETED=0
IN_PROGRESS=0
TOTAL=0

aws s3api list-objects-v2 \\
    --bucket "\$SOURCE_BUCKET" \\
    --prefix "\$PREFIX" \\
    --query 'Contents[?StorageClass==\`DEEP_ARCHIVE\`].Key' \\
    --output text | while read KEY; do

    ((TOTAL++))

    STATUS=\$(aws s3api head-object \\
        --bucket "\$SOURCE_BUCKET" \\
        --key "\$KEY" \\
        2>/dev/null | grep '"Restore":' || echo "")

    if [[ "\$STATUS" =~ ongoing-request=\\"false\\" ]]; then
        echo "✓ \$KEY"
        ((COMPLETED++))
    elif [[ "\$STATUS" =~ ongoing-request=\\"true\\" ]]; then
        echo "⟳ \$KEY"
        ((IN_PROGRESS++))
    else
        echo "○ \$KEY"
    fi
done

echo ""
echo "Summary:"
echo "  Completed: \$COMPLETED"
echo "  In Progress: \$IN_PROGRESS"
echo "  Total: \$TOTAL"

if [ \$COMPLETED -eq \$TOTAL ]; then
    echo ""
    echo "✓ All objects restored!"
    echo "Ready for copy: ./03-copy-selective.sh $SOURCE_BUCKET $TARGET_YEAR $TARGET_TYPE"
fi
EOFMON

chmod +x "$MONITOR_SCRIPT"

echo ""
echo "=========================================="
echo "Next Steps"
echo "=========================================="
echo ""
echo "1. Monitor restore progress:"
echo "   $MONITOR_SCRIPT"
echo ""
echo "2. Check specific object:"
echo "   aws s3api head-object --bucket $SOURCE_BUCKET --key <KEY> | grep Restore"
echo ""
echo "3. After restore completes (~12 hours):"
echo "   ./03-copy-selective.sh $SOURCE_BUCKET $TARGET_YEAR $TARGET_TYPE"
echo ""

# Save restore info
cat > /tmp/restore-info-${TARGET_YEAR}-${TARGET_TYPE}.txt << EOF
SOURCE_BUCKET=$SOURCE_BUCKET
TARGET_YEAR=$TARGET_YEAR
TARGET_TYPE=$TARGET_TYPE
RESTORE_TIER=$RESTORE_TIER
RESTORE_DAYS=$RESTORE_DAYS
OBJECT_COUNT=$OBJECT_COUNT
SIZE_GB=$SIZE_GB
COST=$COST
RESTORE_TIME=$(date +%Y-%m-%d_%H:%M:%S)
PREFIX=$PREFIX
EOF

print_success "Restore requests initiated!"
print_info "Estimated completion: $(date -d '+12 hours' '+%Y-%m-%d %H:%M')"
