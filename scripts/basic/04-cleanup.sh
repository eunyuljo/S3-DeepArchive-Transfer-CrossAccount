#!/bin/bash

##############################################################################
# Script: 04-cleanup.sh
# Purpose: Clean up test resources and data
# Usage: ./04-cleanup.sh [--all] [--keep-buckets]
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

# Parse arguments
CLEANUP_ALL=false
KEEP_BUCKETS=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --all)
            CLEANUP_ALL=true
            shift
            ;;
        --keep-buckets)
            KEEP_BUCKETS=true
            shift
            ;;
        *)
            echo "Usage: $0 [--all] [--keep-buckets]"
            echo "  --all          : Delete all resources including Terraform state"
            echo "  --keep-buckets : Keep S3 buckets, only delete objects"
            exit 1
            ;;
    esac
done

print_header "S3 Deep Archive Cleanup"

# Get bucket names
SOURCE_BUCKET=""
TARGET_BUCKET=""

if [ -f "/tmp/source-bucket-name.txt" ]; then
    SOURCE_BUCKET=$(cat /tmp/source-bucket-name.txt)
fi

if [ -d "../target-account" ]; then
    cd ../target-account
    TARGET_BUCKET=$(terraform output -raw target_bucket_name 2>/dev/null || echo "")
    cd - > /dev/null
fi

if [ -d "../source-account" ]; then
    cd ../source-account
    if [ -z "$SOURCE_BUCKET" ]; then
        SOURCE_BUCKET=$(terraform output -raw source_bucket_name 2>/dev/null || echo "")
    fi
    cd - > /dev/null
fi

print_info "Source Bucket: ${SOURCE_BUCKET:-Not found}"
print_info "Target Bucket: ${TARGET_BUCKET:-Not found}"

# Cleanup options
print_header "Cleanup Options"
echo "1. Clean S3 objects only"
echo "2. Clean S3 objects and local test data"
echo "3. Full cleanup (destroy Terraform resources)"
echo "4. Cancel"
echo ""
read -p "Select option (1-4): " -n 1 -r
echo ""

case $REPLY in
    1)
        print_info "Cleaning S3 objects only..."
        CLEAN_S3=true
        CLEAN_LOCAL=false
        CLEAN_TERRAFORM=false
        ;;
    2)
        print_info "Cleaning S3 objects and local data..."
        CLEAN_S3=true
        CLEAN_LOCAL=true
        CLEAN_TERRAFORM=false
        ;;
    3)
        print_warning "Full cleanup will destroy all Terraform resources!"
        read -p "Are you sure? (yes/no): " CONFIRM
        if [ "$CONFIRM" != "yes" ]; then
            print_info "Cancelled"
            exit 0
        fi
        CLEAN_S3=true
        CLEAN_LOCAL=true
        CLEAN_TERRAFORM=true
        ;;
    4)
        print_info "Cleanup cancelled"
        exit 0
        ;;
    *)
        print_error "Invalid option"
        exit 1
        ;;
esac

# Clean S3 objects
if [ "$CLEAN_S3" = true ]; then
    print_header "Cleaning S3 Objects"

    # Clean source bucket
    if [ -n "$SOURCE_BUCKET" ]; then
        print_info "Cleaning source bucket: $SOURCE_BUCKET"

        # Check if bucket exists
        if aws s3 ls "s3://${SOURCE_BUCKET}" > /dev/null 2>&1; then
            # List objects
            OBJECT_COUNT=$(aws s3 ls "s3://${SOURCE_BUCKET}/deep-archive/" --recursive | wc -l)

            if [ "$OBJECT_COUNT" -gt 0 ]; then
                print_info "Found $OBJECT_COUNT objects in deep-archive/"

                # Remove objects
                if aws s3 rm "s3://${SOURCE_BUCKET}/deep-archive/" --recursive; then
                    print_success "Removed objects from deep-archive/"
                else
                    print_warning "Failed to remove some objects"
                fi
            else
                print_info "No objects in deep-archive/"
            fi

            # Clean standard prefix if exists
            if aws s3 ls "s3://${SOURCE_BUCKET}/standard/" > /dev/null 2>&1; then
                aws s3 rm "s3://${SOURCE_BUCKET}/standard/" --recursive
                print_success "Removed objects from standard/"
            fi
        else
            print_warning "Source bucket not found or not accessible"
        fi
    fi

    # Clean target bucket
    if [ -n "$TARGET_BUCKET" ]; then
        print_info "Cleaning target bucket: $TARGET_BUCKET"

        if aws s3 ls "s3://${TARGET_BUCKET}" > /dev/null 2>&1; then
            OBJECT_COUNT=$(aws s3 ls "s3://${TARGET_BUCKET}/restored/" --recursive | wc -l)

            if [ "$OBJECT_COUNT" -gt 0 ]; then
                print_info "Found $OBJECT_COUNT objects in restored/"

                if aws s3 rm "s3://${TARGET_BUCKET}/restored/" --recursive; then
                    print_success "Removed objects from restored/"
                else
                    print_warning "Failed to remove some objects"
                fi
            else
                print_info "No objects in restored/"
            fi
        else
            print_warning "Target bucket not found or not accessible"
        fi
    fi

    # Delete buckets if not keeping them
    if [ "$KEEP_BUCKETS" = false ] && [ "$CLEAN_TERRAFORM" = false ]; then
        print_header "Deleting Buckets"

        if [ -n "$SOURCE_BUCKET" ]; then
            print_info "Deleting source bucket: $SOURCE_BUCKET"
            if aws s3 rb "s3://${SOURCE_BUCKET}" --force 2>/dev/null; then
                print_success "Deleted source bucket"
            else
                print_warning "Could not delete source bucket (may have versioned objects)"
                print_info "Purge versions and delete markers:"
                echo "aws s3api delete-objects --bucket $SOURCE_BUCKET \\"
                echo "  --delete \"\$(aws s3api list-object-versions \\"
                echo "    --bucket $SOURCE_BUCKET \\"
                echo "    --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}')\" && \\"
                echo "aws s3 rb s3://$SOURCE_BUCKET --force"
            fi
        fi

        if [ -n "$TARGET_BUCKET" ]; then
            print_info "Deleting target bucket: $TARGET_BUCKET"
            if aws s3 rb "s3://${TARGET_BUCKET}" --force 2>/dev/null; then
                print_success "Deleted target bucket"
            else
                print_warning "Could not delete target bucket"
            fi
        fi
    fi
fi

# Clean local files
if [ "$CLEAN_LOCAL" = true ]; then
    print_header "Cleaning Local Files"

    # Test data
    if [ -d "../test-data/sample-files" ]; then
        print_info "Removing test data..."
        rm -rf ../test-data/sample-files/*
        print_success "Test data removed"
    fi

    # Temp files
    print_info "Removing temporary files..."
    rm -f /tmp/source-bucket-name.txt
    rm -f /tmp/restore-info.txt
    rm -f /tmp/monitor-restore-*.sh
    rm -f /tmp/copy-report-*.txt
    print_success "Temporary files removed"
fi

# Clean Terraform resources
if [ "$CLEAN_TERRAFORM" = true ]; then
    print_header "Destroying Terraform Resources"

    # Target account
    if [ -d "../target-account" ]; then
        print_info "Destroying target account resources..."
        cd ../target-account

        # Remove IAM user access keys first
        IAM_USER=$(terraform output -raw iam_user_name 2>/dev/null || echo "")
        if [ -n "$IAM_USER" ] && [ "$IAM_USER" != "N/A" ]; then
            print_info "Removing IAM user access keys..."
            ACCESS_KEYS=$(aws iam list-access-keys --user-name "$IAM_USER" \
                --query 'AccessKeyMetadata[].AccessKeyId' --output text 2>/dev/null || echo "")

            for key in $ACCESS_KEYS; do
                aws iam delete-access-key --user-name "$IAM_USER" --access-key-id "$key" 2>/dev/null || true
            done
        fi

        terraform destroy -auto-approve
        print_success "Target account resources destroyed"
        cd - > /dev/null
    fi

    # Source account
    if [ -d "../source-account" ]; then
        print_info "Destroying source account resources..."
        cd ../source-account
        terraform destroy -auto-approve
        print_success "Source account resources destroyed"
        cd - > /dev/null
    fi

    # Remove terraform state backups
    print_info "Cleaning Terraform state backups..."
    find ../source-account ../target-account -name "*.tfstate*" -type f -delete 2>/dev/null || true
    find ../source-account ../target-account -name ".terraform" -type d -exec rm -rf {} + 2>/dev/null || true
    print_success "Terraform state cleaned"
fi

# Final summary
print_header "Cleanup Summary"

if [ "$CLEAN_S3" = true ]; then
    echo "✓ S3 objects cleaned"
fi

if [ "$CLEAN_LOCAL" = true ]; then
    echo "✓ Local files cleaned"
fi

if [ "$CLEAN_TERRAFORM" = true ]; then
    echo "✓ Terraform resources destroyed"
fi

print_success "Cleanup complete!"

# Show remaining resources
print_header "Remaining Resources"

if [ -n "$SOURCE_BUCKET" ]; then
    if aws s3 ls "s3://${SOURCE_BUCKET}" > /dev/null 2>&1; then
        print_info "Source bucket still exists: $SOURCE_BUCKET"
    fi
fi

if [ -n "$TARGET_BUCKET" ]; then
    if aws s3 ls "s3://${TARGET_BUCKET}" > /dev/null 2>&1; then
        print_info "Target bucket still exists: $TARGET_BUCKET"
    fi
fi

# Helpful commands
echo ""
print_info "Useful commands for manual cleanup:"
echo ""
echo "# List all buckets:"
echo "aws s3 ls"
echo ""
echo "# Force delete bucket with versions:"
echo "aws s3api delete-objects --bucket BUCKET_NAME \\"
echo "  --delete \"\$(aws s3api list-object-versions --bucket BUCKET_NAME \\"
echo "  --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}')\""
echo ""
echo "# List IAM users:"
echo "aws iam list-users"
echo ""
