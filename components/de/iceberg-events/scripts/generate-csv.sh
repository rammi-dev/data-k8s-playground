#!/bin/bash
# Generate a test CSV and upload to s3://iceberg-events/raw/test-table/
# Triggers CephBucketNotification → Kafka event
set -e

# Determine project root
if [[ -d "/vagrant" ]]; then
    PROJECT_ROOT="/vagrant"
elif [[ -n "${PROJECT_ROOT:-}" ]]; then
    :
else
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
fi

NAMESPACE="rook-ceph"
BUCKET_NAME="iceberg-events"
S3_ACCESS_KEY="minio"
S3_SECRET_KEY="minio123"
LOCAL_PORT=7482

source "$PROJECT_ROOT/scripts/common/utils.sh"

# Ensure port-forward is running
if ! ss -tlnp 2>/dev/null | grep -q ":$LOCAL_PORT "; then
    print_info "Starting port-forward to RGW on :$LOCAL_PORT..."
    kubectl -n "$NAMESPACE" port-forward svc/rook-ceph-rgw-s3-store "$LOCAL_PORT:80" &>/dev/null &
    sleep 2
fi

S3_ENDPOINT="http://localhost:$LOCAL_PORT"
export AWS_ACCESS_KEY_ID="$S3_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$S3_SECRET_KEY"
export AWS_DEFAULT_REGION="us-east-1"
aws configure set default.s3.addressing_style path

# Generate random suffix
SUFFIX=$(head -c 4 /dev/urandom | xxd -p)
FILE="iceberg-${SUFFIX}.csv"
TMPFILE="/tmp/$FILE"

# Generate CSV with sample data
print_info "Generating $FILE..."
cat > "$TMPFILE" <<CSV
id,name,city,amount,created_at
1,Alice,New York,120.50,2025-01-15T10:30:00Z
2,Bob,London,85.00,2025-01-15T11:00:00Z
3,Charlie,Tokyo,200.75,2025-01-15T11:30:00Z
4,Diana,Berlin,45.20,2025-01-15T12:00:00Z
5,Eve,Sydney,310.00,2025-01-15T12:30:00Z
CSV

# Upload to S3
S3_PATH="s3://$BUCKET_NAME/raw/test-table/$FILE"
print_info "Uploading to $S3_PATH..."
aws s3 cp "$TMPFILE" "$S3_PATH" --endpoint-url "$S3_ENDPOINT"

rm -f "$TMPFILE"

print_success "Uploaded $FILE → $S3_PATH"
print_info "S3 notification event should appear on Kafka topic 'iceberg-events-topic'"
