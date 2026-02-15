#!/bin/bash
# Ingest CSV files into an Iceberg table using PyIceberg
# Auto-detects S3 mode when OBC exists, starts port-forward as needed
set -e

# Determine project root (works from any location)
if [[ -d "/vagrant" ]]; then
    PROJECT_ROOT="/vagrant"
elif [[ -n "${PROJECT_ROOT:-}" ]]; then
    : # Use existing PROJECT_ROOT
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

print_info "Iceberg CSV Ingestion"
echo "=========================================="

# Check uv is available
if ! command -v uv &>/dev/null; then
    print_error "uv is not installed"
    print_info "Install with: curl -LsSf https://astral.sh/uv/install.sh | sh"
    exit 1
fi

# Sync dependencies (creates venv if needed)
print_info "Syncing dependencies..."
uv sync --project "$COMPONENT_DIR"

# Clean previous output for a fresh run
if [[ -d "$COMPONENT_DIR/output" ]]; then
    print_info "Cleaning previous output..."
    rm -rf "$COMPONENT_DIR/output"
fi

# ============================================================================
# Auto-detect S3 mode: if OBC exists and S3 env vars are not already set
# ============================================================================
PF_PID=""
cleanup() {
    if [[ -n "$PF_PID" ]]; then
        kill "$PF_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT

if [[ -z "${S3_ENDPOINT:-}" ]] && kubectl -n "$NAMESPACE" get obc "$OBC_NAME" -o jsonpath='{.status.phase}' 2>/dev/null | grep -q "Bound"; then
    print_info "Detected OBC '$OBC_NAME' — configuring S3 mode..."

    # Start port-forward if not already running on LOCAL_PORT
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

    print_success "S3 configured: bucket=$BUCKET_NAME endpoint=$S3_ENDPOINT"
fi

# Run ingestion
print_info "Running ingestion script..."
"$COMPONENT_DIR/.venv/bin/python" "$COMPONENT_DIR/ingest.py"

print_success "Ingestion complete!"
