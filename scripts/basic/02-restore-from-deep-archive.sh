#!/bin/bash

##############################################################################
# Script: 02-restore-from-deep-archive.sh
# Purpose: Restore objects from S3 Deep Archive
# Usage: ./02-restore-from-deep-archive.sh [source-bucket-name] [tier]
# Tiers: Bulk (default, 12h) or Standard (12h)
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
RESTORE_TIER=${2:-Bulk}  # Bulk or Standard
RESTORE_DAYS=${3:-7}     # Days to keep restored data

if [ -z "$SOURCE_BUCKET" ]; then
    # Try to get from previous script
    if [ -f "/tmp/source-bucket-name.txt" ]; then
        SOURCE_BUCKET=$(cat /tmp/source-bucket-name.txt)
    else
        print_error "Source bucket name required."
        echo "Usage: $0 <source-bucket-name> [tier] [days]"
        echo "  tier: Bulk (default) or Standard"
        echo "  days: Number of days to keep restored data (default: 7)"
        exit 1
    fi
fi

# Validate tier
if [[ ! "$RESTORE_TIER" =~ ^(Bulk|Standard)$ ]]; then
    print_error "Invalid tier. Use 'Bulk' or 'Standard'"
    exit 1
fi

print_header "S3 Deep Archive Restore"
print_info "Source Bucket: $SOURCE_BUCKET"
print_info "Restore Tier: $RESTORE_TIER"
print_info "Restore Days: $RESTORE_DAYS"

# Tier information
case $RESTORE_TIER in
    Bulk)
        print_info "Bulk tier: 12 hours, $0.025/GB"
        ;;
    Standard)
        print_info "Standard tier: 12 hours, $0.10/GB"
        ;;
esac

# List objects in Deep Archive
print_info "Listing objects in deep-archive/..."

OBJECTS=$(aws s3api list-objects-v2 \
    --bucket "$SOURCE_BUCKET" \
    --prefix "deep-archive/" \
    --query 'Contents[].Key' \
    --output text)

if [ -z "$OBJECTS" ]; then
    print_error "No objects found in deep-archive/ prefix"
    exit 1
fi

print_success "Found objects to restore:"
echo "$OBJECTS" | tr '\t' '\n' | while read obj; do
    echo "  - $obj"
done

# Count objects
OBJECT_COUNT=$(echo "$OBJECTS" | wc -w)
print_info "Total objects: $OBJECT_COUNT"

# Confirm restore
echo ""
read -p "Proceed with restore? (y/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_info "Restore cancelled"
    exit 0
fi

# Restore each object
print_header "Initiating Restore Requests"

RESTORE_SUCCESS=0
ALREADY_RESTORED=0
RESTORE_FAILED=0

for key in $OBJECTS; do
    print_info "Restoring: $key"

    # Check current restore status
    RESTORE_STATUS=$(aws s3api head-object \
        --bucket "$SOURCE_BUCKET" \
        --key "$key" \
        2>/dev/null | grep -o '"Restore": "[^"]*"' || echo "")

    if [[ "$RESTORE_STATUS" =~ ongoing-request=\"true\" ]]; then
        print_warning "Restore already in progress for $key"
        ((ALREADY_RESTORED++))
        continue
    elif [[ "$RESTORE_STATUS" =~ ongoing-request=\"false\" ]]; then
        print_warning "Object already restored: $key"
        ((ALREADY_RESTORED++))
        continue
    fi

    # Initiate restore
    RESTORE_REQUEST="{\"Days\":${RESTORE_DAYS},\"GlacierJobParameters\":{\"Tier\":\"${RESTORE_TIER}\"}}"

    if aws s3api restore-object \
        --bucket "$SOURCE_BUCKET" \
        --key "$key" \
        --restore-request "$RESTORE_REQUEST" 2>/dev/null; then

        print_success "Restore initiated: $key"
        ((RESTORE_SUCCESS++))
    else
        # Check if already restored
        ERROR_CODE=$?
        if [ $ERROR_CODE -eq 254 ]; then
            print_warning "Object may already be restored: $key"
            ((ALREADY_RESTORED++))
        else
            print_error "Failed to restore: $key"
            ((RESTORE_FAILED++))
        fi
    fi

    # Small delay to avoid throttling
    sleep 0.5
done

# Summary
print_header "Restore Summary"
echo "Restore requests sent: ${RESTORE_SUCCESS}"
echo "Already restored/in progress: ${ALREADY_RESTORED}"
echo "Failed: ${RESTORE_FAILED}"
echo ""

if [ $RESTORE_SUCCESS -gt 0 ]; then
    print_info "Restoration ETA: ~12 hours"
    print_info "Restored data will be available for ${RESTORE_DAYS} days"
fi

# Create monitoring script
MONITOR_SCRIPT="/tmp/monitor-restore-${SOURCE_BUCKET}.sh"
cat > "$MONITOR_SCRIPT" << 'EOFMON'
#!/bin/bash

SOURCE_BUCKET="$1"
OBJECTS="$2"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "Checking restore status for bucket: $SOURCE_BUCKET"
echo ""

COMPLETED=0
IN_PROGRESS=0
NOT_STARTED=0

for key in $OBJECTS; do
    STATUS=$(aws s3api head-object \
        --bucket "$SOURCE_BUCKET" \
        --key "$key" \
        2>/dev/null | grep '"Restore":' || echo "")

    if [[ "$STATUS" =~ ongoing-request=\"false\" ]]; then
        echo -e "${GREEN}✓${NC} Completed: $key"
        ((COMPLETED++))
    elif [[ "$STATUS" =~ ongoing-request=\"true\" ]]; then
        echo -e "${YELLOW}⟳${NC} In Progress: $key"
        ((IN_PROGRESS++))
    else
        echo -e "${BLUE}○${NC} Not Started: $key"
        ((NOT_STARTED++))
    fi
done

echo ""
echo "Status Summary:"
echo "  Completed: $COMPLETED"
echo "  In Progress: $IN_PROGRESS"
echo "  Not Started: $NOT_STARTED"

if [ $COMPLETED -eq $(echo "$OBJECTS" | wc -w) ]; then
    echo ""
    echo "All objects restored! Ready for copy."
    echo "Next: ./03-cross-account-copy.sh"
fi
EOFMON

chmod +x "$MONITOR_SCRIPT"

print_header "Next Steps"
echo "1. Wait for restore to complete (~12 hours)"
echo ""
echo "2. Monitor status with:"
echo "   $MONITOR_SCRIPT \"$SOURCE_BUCKET\" \"$OBJECTS\""
echo ""
echo "3. Or check individual object:"
echo "   aws s3api head-object \\"
echo "       --bucket $SOURCE_BUCKET \\"
echo "       --key deep-archive/filename.txt \\"
echo "       | grep Restore"
echo ""
echo "4. When restore is complete, run:"
echo "   ./03-cross-account-copy.sh $SOURCE_BUCKET"
echo ""

# Save info for next script
cat > /tmp/restore-info.txt << EOF
SOURCE_BUCKET=$SOURCE_BUCKET
RESTORE_TIER=$RESTORE_TIER
RESTORE_DAYS=$RESTORE_DAYS
OBJECTS=$OBJECTS
RESTORE_TIME=$(date +%Y-%m-%d_%H:%M:%S)
EOF

print_success "Restore requests completed!"

# Quick status check
echo ""
print_info "Current status check:"
$MONITOR_SCRIPT "$SOURCE_BUCKET" "$OBJECTS"
