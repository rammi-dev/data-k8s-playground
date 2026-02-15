#!/bin/bash
# Create Iceberg S3 infrastructure: bucket (OBC) + operating user + upload CSVs
# Requires: Ceph S3 object store deployed (s3-store in rook-ceph namespace)
set -e

# Determine project root
if [[ -d "/vagrant" ]]; then
    PROJECT_ROOT="/vagrant"
elif [[ -n "${PROJECT_ROOT:-}" ]]; then
    :
else
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../../.." && pwd)"
fi

INFRA_DIR="$PROJECT_ROOT/components/de/iceberg/infra"
UPLOAD_DIR="$PROJECT_ROOT/components/de/iceberg/upload"
NAMESPACE="rook-ceph"

OBC_NAME="iceberg-upload"
USER_SECRET="rook-ceph-object-user-s3-store-minio"
S3_ACCESS_KEY="minio"
S3_SECRET_KEY="minio123"

source "$PROJECT_ROOT/scripts/common/utils.sh"

print_info "Iceberg S3 Infrastructure Setup"
echo "=========================================="

# Pre-flight: check S3 object store exists
if ! kubectl -n "$NAMESPACE" get cephobjectstore s3-store &>/dev/null; then
    print_error "CephObjectStore 's3-store' not found"
    print_info "Deploy Ceph first: ./components/ceph/scripts/build.sh"
    exit 1
fi
print_success "CephObjectStore 's3-store' found"

# ============================================================================
# STEP 1: Create bucket via ObjectBucketClaim
# ============================================================================
print_info "Step 1: Creating bucket via ObjectBucketClaim..."
kubectl apply -f "$INFRA_DIR/manifests/bucket-claim.yaml"

print_info "  Waiting for OBC to be Bound..."
for i in {1..60}; do
    STATUS=$(kubectl -n "$NAMESPACE" get obc "$OBC_NAME" -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
    if [[ "$STATUS" == "Bound" ]]; then
        print_success "  OBC bound"
        break
    fi
    [[ "$i" -eq 60 ]] && { print_error "OBC not bound after 60s"; kubectl -n "$NAMESPACE" describe obc "$OBC_NAME"; exit 1; }
    sleep 1
done

# Read bucket name from OBC ConfigMap
BUCKET_NAME=$(kubectl -n "$NAMESPACE" get cm "$OBC_NAME" -o jsonpath='{.data.BUCKET_NAME}')
print_success "  Bucket: $BUCKET_NAME"

# ============================================================================
# STEP 2: Create S3 operating user (keys from Secret)
# ============================================================================
print_info "Step 2: Creating S3 operating user..."
kubectl apply -f "$INFRA_DIR/manifests/s3-user.yaml"

print_info "  Waiting for user secret..."
for i in {1..30}; do
    if kubectl -n "$NAMESPACE" get secret "$USER_SECRET" &>/dev/null; then
        print_success "  User secret '$USER_SECRET' ready"
        break
    fi
    [[ "$i" -eq 30 ]] && { print_error "User secret not created after 30s"; exit 1; }
    sleep 1
done

# ============================================================================
# STEP 3: Upload CSV files using operating user
# ============================================================================
print_info "Step 3: Uploading CSV files to S3..."

# Port-forward for WSL access to RGW
LOCAL_PORT=7481
kubectl -n "$NAMESPACE" port-forward svc/rook-ceph-rgw-s3-store "$LOCAL_PORT:80" &>/dev/null &
PF_PID=$!
sleep 2

if ! kill -0 $PF_PID 2>/dev/null; then
    print_error "Port-forward failed"
    exit 1
fi

export AWS_ACCESS_KEY_ID="$S3_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$S3_SECRET_KEY"
export AWS_ENDPOINT_URL="http://localhost:$LOCAL_PORT"
export AWS_DEFAULT_REGION="us-east-1"

CSV_DIR="$UPLOAD_DIR/csv"
for csv_file in "$CSV_DIR"/*.csv; do
    filename=$(basename "$csv_file")
    aws s3 cp "$csv_file" "s3://$BUCKET_NAME/csv/$filename"
    print_success "  Uploaded: $filename"
done

print_info "  Verifying uploads..."
aws s3 ls "s3://$BUCKET_NAME/csv/"

# Kill temporary port-forward
kill $PF_PID 2>/dev/null || true

# ============================================================================
# DONE
# ============================================================================
print_success "Iceberg S3 Infrastructure Ready!"
echo "=========================================="
echo ""
print_info "Bucket:       $BUCKET_NAME"
print_info "Access Key:   $S3_ACCESS_KEY"
print_info "Secret Key:   $S3_SECRET_KEY"
echo ""
print_info "Run ingestion (handles port-forward automatically):"
echo "  cd $UPLOAD_DIR && ./scripts/ingest.sh"
echo ""
print_info "Or run manually:"
echo "  kubectl -n $NAMESPACE port-forward svc/rook-ceph-rgw-s3-store 7481:80 &"
echo "  export S3_ENDPOINT=http://localhost:7481"
echo "  export S3_BUCKET=$BUCKET_NAME"
echo "  export AWS_ACCESS_KEY_ID=$S3_ACCESS_KEY"
echo "  export AWS_SECRET_ACCESS_KEY=$S3_SECRET_KEY"
echo "  cd $UPLOAD_DIR && uv sync && .venv/bin/python ingest.py"
echo ""
print_info "Destroy:"
echo "  $INFRA_DIR/scripts/destroy.sh"
