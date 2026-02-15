#!/bin/bash
# Start port-forward to RGW S3 endpoint and export env vars for aws CLI / Python
# Usage: source ./scripts/port-forward.sh
set -e

NAMESPACE="rook-ceph"
LOCAL_PORT=7481
S3_ACCESS_KEY="minio"
S3_SECRET_KEY="minio123"
BUCKET_NAME="iceberg-upload"

if ss -tlnp 2>/dev/null | grep -q ":$LOCAL_PORT "; then
    echo "Port-forward already running on :$LOCAL_PORT"
else
    kubectl -n "$NAMESPACE" port-forward svc/rook-ceph-rgw-s3-store "$LOCAL_PORT:80" &>/dev/null &
    sleep 2
    if ! ss -tlnp 2>/dev/null | grep -q ":$LOCAL_PORT "; then
        echo "ERROR: Port-forward failed"
        return 1 2>/dev/null || exit 1
    fi
    echo "Port-forward started on :$LOCAL_PORT"
fi

export S3_ENDPOINT="http://localhost:$LOCAL_PORT"
export S3_BUCKET="$BUCKET_NAME"
export AWS_ACCESS_KEY_ID="$S3_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$S3_SECRET_KEY"
export AWS_DEFAULT_REGION="us-east-1"

# Path-style for localhost
aws configure set default.s3.addressing_style path 2>/dev/null || true

echo "Exported: S3_ENDPOINT=$S3_ENDPOINT S3_BUCKET=$S3_BUCKET AWS_ACCESS_KEY_ID=$S3_ACCESS_KEY"
echo ""
echo "Activate venv:  source .venv/bin/activate"
echo "Stop:           pkill -f 'port-forward.*$LOCAL_PORT'"
