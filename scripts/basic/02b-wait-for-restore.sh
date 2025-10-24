#!/bin/bash

##############################################################################
# Script: 02b-wait-for-restore.sh
# Purpose: Wait for Deep Archive restore to complete (blocking)
# Usage: ./02b-wait-for-restore.sh [source-bucket-name]
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

# Get source bucket
SOURCE_BUCKET=${1:-}

if [ -z "$SOURCE_BUCKET" ]; then
    if [ -f "/tmp/source-bucket-name.txt" ]; then
        SOURCE_BUCKET=$(cat /tmp/source-bucket-name.txt)
    else
        print_error "Source bucket name required."
        echo "Usage: $0 <source-bucket-name>"
        exit 1
    fi
fi

print_header "Waiting for Deep Archive Restore"
print_info "Source Bucket: $SOURCE_BUCKET"

# Get object list from restore info
if [ -f "/tmp/restore-info.txt" ]; then
    source /tmp/restore-info.txt
else
    print_error "No restore info found. Run 02-restore-from-deep-archive.sh first."
    exit 1
fi

if [ -z "$OBJECTS" ]; then
    print_error "No objects to monitor"
    exit 1
fi

OBJECT_ARRAY=($OBJECTS)
TOTAL_OBJECTS=${#OBJECT_ARRAY[@]}

print_info "Monitoring $TOTAL_OBJECTS objects for restore completion"
print_info "Restore tier: $RESTORE_TIER"
print_info "Expected completion: ~12 hours from restore request"
print_info "Started at: $RESTORE_TIME"
echo ""

# Check interval (5 minutes)
CHECK_INTERVAL=300

# Initial wait (don't check immediately)
print_info "Initial wait: 30 minutes before first check..."
sleep 1800

ITERATION=1
START_TIME=$(date +%s)

while true; do
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - START_TIME))
    ELAPSED_HOURS=$((ELAPSED / 3600))
    ELAPSED_MINS=$(((ELAPSED % 3600) / 60))

    print_header "Check #$ITERATION - Elapsed: ${ELAPSED_HOURS}h ${ELAPSED_MINS}m"

    COMPLETED=0
    IN_PROGRESS=0
    NOT_STARTED=0

    for key in "${OBJECT_ARRAY[@]}"; do
        # Get restore status
        STATUS=$(aws s3api head-object \
            --bucket "$SOURCE_BUCKET" \
            --key "$key" \
            2>/dev/null | grep '"Restore":' || echo "")

        if [[ "$STATUS" =~ ongoing-request=\"false\" ]]; then
            print_success "✓ Completed: $key"
            ((COMPLETED++))
        elif [[ "$STATUS" =~ ongoing-request=\"true\" ]]; then
            print_info "⟳ In Progress: $key"
            ((IN_PROGRESS++))
        else
            print_warning "○ Not Started: $key"
            ((NOT_STARTED++))
        fi
    done

    echo ""
    echo "Status Summary:"
    echo "  ✓ Completed: $COMPLETED / $TOTAL_OBJECTS"
    echo "  ⟳ In Progress: $IN_PROGRESS / $TOTAL_OBJECTS"
    echo "  ○ Not Started: $NOT_STARTED / $TOTAL_OBJECTS"

    # Check if all completed
    if [ $COMPLETED -eq $TOTAL_OBJECTS ]; then
        echo ""
        print_success "=========================================="
        print_success "All objects restored successfully!"
        print_success "=========================================="
        echo ""
        print_info "Total wait time: ${ELAPSED_HOURS}h ${ELAPSED_MINS}m"
        echo ""
        print_info "Ready to proceed with cross-account copy:"
        echo "  ./03-cross-account-copy.sh $SOURCE_BUCKET"
        echo ""
        exit 0
    fi

    # Estimate remaining time
    if [ $IN_PROGRESS -gt 0 ]; then
        # Assume 12 hours total, estimate based on elapsed time
        ESTIMATED_TOTAL=43200  # 12 hours in seconds
        REMAINING=$((ESTIMATED_TOTAL - ELAPSED))

        if [ $REMAINING -gt 0 ]; then
            REMAINING_HOURS=$((REMAINING / 3600))
            REMAINING_MINS=$(((REMAINING % 3600) / 60))
            echo ""
            print_info "Estimated remaining: ~${REMAINING_HOURS}h ${REMAINING_MINS}m"
        fi
    fi

    # Wait before next check
    echo ""
    print_info "Next check in 5 minutes... (Ctrl+C to stop)"
    sleep $CHECK_INTERVAL

    ((ITERATION++))
done
