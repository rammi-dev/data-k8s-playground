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
BUCKET_NAME="iceberg-upload"
USER_SECRET="rook-ceph-object-user-s3-store-minio"
S3_ACCESS_KEY="minio"
S3_SECRET_KEY="minio123"

LOCAL_PORT=7481

source "$PROJECT_ROOT/scripts/common/utils.sh"

# Start a port-forward to RGW if not already running, set S3_OPTS for aws CLI
ensure_port_forward() {
    if ss -tlnp 2>/dev/null | grep -q ":$LOCAL_PORT "; then
        print_info "  Port-forward already running on :$LOCAL_PORT"
    else
        kubectl -n "$NAMESPACE" port-forward svc/rook-ceph-rgw-s3-store "$LOCAL_PORT:80" &>/dev/null &
        PF_PID=$!
        sleep 2
        if ! kill -0 $PF_PID 2>/dev/null; then
            print_error "Port-forward failed"
            exit 1
        fi
        print_success "  Port-forward started on :$LOCAL_PORT (PID $PF_PID)"
    fi
    S3_ENDPOINT="http://localhost:$LOCAL_PORT"
    S3_OPTS="--endpoint-url $S3_ENDPOINT"
    export AWS_DEFAULT_REGION="us-east-1"
    # RGW requires path-style addressing (virtual-hosted won't work with localhost)
    aws configure set default.s3.addressing_style path
}

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

print_success "  Bucket: $BUCKET_NAME"

# ============================================================================
# STEP 2: Create S3 operating user (keys from Secret)
# ============================================================================
print_info "Step 2: Creating S3 operating user..."

# If user is stuck in ReconcileFailed (missing keys secret), fix it first
USER_PHASE=$(kubectl -n "$NAMESPACE" get cephobjectstoreuser minio -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
if [[ "$USER_PHASE" == "ReconcileFailed" ]]; then
    print_info "  User stuck in ReconcileFailed, cleaning up..."
    kubectl apply -f "$INFRA_DIR/manifests/s3-user.yaml"
    sleep 5
    kubectl delete cephobjectstoreuser minio -n "$NAMESPACE" --ignore-not-found
    kubectl wait --for=delete cephobjectstoreuser/minio -n "$NAMESPACE" --timeout=30s 2>/dev/null || true
    kubectl delete secret iceberg-s3-keys -n "$NAMESPACE" --ignore-not-found
    print_success "  Cleaned up stuck user"
fi

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
# STEP 3: Grant minio user access to OBC bucket via bucket policy
# ============================================================================
print_info "Step 3: Granting minio user access to bucket..."

ensure_port_forward

# Use OBC owner credentials to set bucket policy
OBC_ACCESS_KEY=$(kubectl -n "$NAMESPACE" get secret "$OBC_NAME" -o jsonpath='{.data.AWS_ACCESS_KEY_ID}' | base64 -d)
OBC_SECRET_KEY=$(kubectl -n "$NAMESPACE" get secret "$OBC_NAME" -o jsonpath='{.data.AWS_SECRET_ACCESS_KEY}' | base64 -d)

POLICY=$(cat <<POLICYEOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {"AWS": ["arn:aws:iam:::user/minio"]},
      "Action": "s3:*",
      "Resource": [
        "arn:aws:s3:::${BUCKET_NAME}",
        "arn:aws:s3:::${BUCKET_NAME}/*"
      ]
    }
  ]
}
POLICYEOF
)

AWS_ACCESS_KEY_ID="$OBC_ACCESS_KEY" AWS_SECRET_ACCESS_KEY="$OBC_SECRET_KEY" \
    aws s3api put-bucket-policy --bucket "$BUCKET_NAME" --policy "$POLICY" $S3_OPTS
print_success "  Bucket policy applied"

# ============================================================================
# STEP 4: Upload source files (csv + zip) using minio user
# ============================================================================
print_info "Step 4: Uploading source files to S3..."

export AWS_ACCESS_KEY_ID="$S3_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$S3_SECRET_KEY"

SOURCE_DIR="$UPLOAD_DIR/source"

for csv_file in "$SOURCE_DIR/csv"/*.csv; do
    filename=$(basename "$csv_file")
    aws s3 cp "$csv_file" "s3://$BUCKET_NAME/source/csv/$filename" $S3_OPTS
    print_success "  Uploaded: csv/$filename"
done

aws s3 cp "$SOURCE_DIR/zip/" "s3://$BUCKET_NAME/source/zip/" --recursive --include "*.zip" $S3_OPTS
print_success "  Uploaded: zip/"

print_info "  Verifying uploads..."
aws s3 ls "s3://$BUCKET_NAME/source/" --recursive $S3_OPTS

# ============================================================================
# DONE — port-forward left running for subsequent use
# ============================================================================
print_success "Iceberg S3 Infrastructure Ready!"
echo "=========================================="
echo ""
print_info "Bucket:       $BUCKET_NAME"
print_info "Access Key:   $S3_ACCESS_KEY"
print_info "Secret Key:   $S3_SECRET_KEY"
print_info "S3 Endpoint:  http://localhost:$LOCAL_PORT (port-forward running)"
echo ""
print_info "Run ingestion:"
echo "  cd $UPLOAD_DIR && ./scripts/ingest.sh"
echo ""
print_info "Or run manually:"
echo "  export AWS_ACCESS_KEY_ID=$S3_ACCESS_KEY"
echo "  export AWS_SECRET_ACCESS_KEY=$S3_SECRET_KEY"
echo "  export AWS_DEFAULT_REGION=us-east-1"
echo "  cd $UPLOAD_DIR && uv sync && .venv/bin/python ingest.py"
echo ""
print_info "Stop port-forward:"
echo "  pkill -f 'port-forward.*$LOCAL_PORT'"
echo ""
print_info "Destroy:"
echo "  $INFRA_DIR/scripts/destroy.sh"
