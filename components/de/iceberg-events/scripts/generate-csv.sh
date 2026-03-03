#!/bin/bash
# Generate test CSVs for table_x (orders) and table_y (sensors) and upload
# to s3://iceberg-events/raw/{table}/
# Triggers CephBucketNotification → Kafka event for each file
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

SUFFIX=$(head -c 4 /dev/urandom | xxd -p)

# ============================================================================
# table_x — orders (id, customer, product, quantity, price, order_date)
# ============================================================================
FILE_X="orders-${SUFFIX}.csv"
TMPFILE_X="/tmp/$FILE_X"

print_info "Generating table_x: $FILE_X (orders schema)..."
cat > "$TMPFILE_X" <<CSV
id,customer,product,quantity,price,order_date
1,Alice,Widget A,3,29.99,2025-06-01T09:15:00Z
2,Bob,Gadget B,1,149.50,2025-06-01T10:30:00Z
3,Charlie,Widget A,5,29.99,2025-06-01T11:00:00Z
4,Diana,Sensor C,2,74.00,2025-06-01T12:45:00Z
5,Eve,Gadget B,1,149.50,2025-06-01T14:20:00Z
CSV

S3_PATH_X="s3://$BUCKET_NAME/raw/table_x/$FILE_X"
print_info "Uploading to $S3_PATH_X..."
aws s3 cp "$TMPFILE_X" "$S3_PATH_X" --endpoint-url "$S3_ENDPOINT"
rm -f "$TMPFILE_X"
print_success "table_x → $S3_PATH_X"

# ============================================================================
# table_y — sensor readings (sensor_id, location, temperature, humidity, battery_pct, reading_ts)
# ============================================================================
FILE_Y="sensors-${SUFFIX}.csv"
TMPFILE_Y="/tmp/$FILE_Y"

print_info "Generating table_y: $FILE_Y (sensor readings schema)..."
cat > "$TMPFILE_Y" <<CSV
sensor_id,location,temperature,humidity,battery_pct,reading_ts
SNS-001,warehouse-a,22.4,45.1,98,2025-06-01T08:00:00Z
SNS-002,warehouse-b,19.8,52.3,87,2025-06-01T08:00:00Z
SNS-003,outdoor-north,31.2,38.7,72,2025-06-01T08:00:00Z
SNS-001,warehouse-a,22.6,44.9,98,2025-06-01T08:05:00Z
SNS-004,cold-storage,4.1,80.2,95,2025-06-01T08:00:00Z
CSV

S3_PATH_Y="s3://$BUCKET_NAME/raw/table_y/$FILE_Y"
print_info "Uploading to $S3_PATH_Y..."
aws s3 cp "$TMPFILE_Y" "$S3_PATH_Y" --endpoint-url "$S3_ENDPOINT"
rm -f "$TMPFILE_Y"
print_success "table_y → $S3_PATH_Y"

# ============================================================================
echo ""
print_success "Both files uploaded — 2 Kafka events expected on topic 'iceberg-events-topic'"
print_info "Run consume.sh to see the events:"
echo "  $(dirname "$0")/consume.sh -b -t 10000"
