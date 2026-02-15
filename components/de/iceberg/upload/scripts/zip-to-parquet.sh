#!/bin/bash
# Convert ZIP files (containing CSVs) from S3 to Parquet
# Reads from source/zip/{batch}/{entity}/, writes to source/parquet/{batch}/{entity}/
#
# Usage:
#   ./zip-to-parquet.sh <batch|all> <entity>
#   ./zip-to-parquet.sh 01 employees     # convert batch 01
#   ./zip-to-parquet.sh all employees    # convert all batches
set -e

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 <batch|all> <entity>"
    echo "  e.g.: $0 01 employees"
    echo "        $0 all employees"
    exit 1
fi

BATCH="$1"
ENTITY="$2"

# Determine project root
if [[ -d "/vagrant" ]]; then
    PROJECT_ROOT="/vagrant"
elif [[ -n "${PROJECT_ROOT:-}" ]]; then
    :
else
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../../.." && pwd)"
fi

COMPONENT_DIR="$PROJECT_ROOT/components/de/iceberg/upload"
NAMESPACE="rook-ceph"
OBC_NAME="iceberg-upload"
BUCKET_NAME="iceberg-upload"
LOCAL_PORT=7481

S3_ACCESS_KEY="minio"
S3_SECRET_KEY="minio123"

source "$PROJECT_ROOT/scripts/common/utils.sh"

print_info "ZIP to Parquet Conversion"
echo "=========================================="
print_info "Batch:  $BATCH"
print_info "Entity: $ENTITY"

# Check uv is available
if ! command -v uv &>/dev/null; then
    print_error "uv is not installed"
    exit 1
fi

# Sync dependencies
print_info "Syncing dependencies..."
uv sync --project "$COMPONENT_DIR" --quiet

# Auto-detect S3 and start port-forward if needed
if [[ -z "${S3_ENDPOINT:-}" ]] && kubectl -n "$NAMESPACE" get obc "$OBC_NAME" -o jsonpath='{.status.phase}' 2>/dev/null | grep -q "Bound"; then
    if ! ss -tlnp 2>/dev/null | grep -q ":$LOCAL_PORT "; then
        print_info "Starting port-forward on localhost:$LOCAL_PORT..."
        kubectl -n "$NAMESPACE" port-forward svc/rook-ceph-rgw-s3-store "$LOCAL_PORT:80" &>/dev/null &
        PF_PID=$!
        sleep 2
        if ! kill -0 "$PF_PID" 2>/dev/null; then
            print_error "Port-forward failed"
            exit 1
        fi
    else
        print_info "Port $LOCAL_PORT already in use, assuming existing port-forward"
    fi

    export S3_ENDPOINT="http://localhost:$LOCAL_PORT"
    export S3_BUCKET="$BUCKET_NAME"
    export AWS_ACCESS_KEY_ID="$S3_ACCESS_KEY"
    export AWS_SECRET_ACCESS_KEY="$S3_SECRET_KEY"
fi

if [[ -z "${S3_ENDPOINT:-}" ]]; then
    print_error "S3 not configured. Set S3_ENDPOINT, S3_BUCKET, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY"
    exit 1
fi

print_success "S3 configured: bucket=$S3_BUCKET endpoint=$S3_ENDPOINT"

# Run conversion
"$COMPONENT_DIR/.venv/bin/python" "$COMPONENT_DIR/zip_to_parquet.py" "$BATCH" "$ENTITY"

print_success "Conversion complete!"
