#!/bin/bash
# Bootstrap iceberg-events: Kafka cluster + S3 bucket + notifications → Kafka
# Requires: Ceph S3 object store (s3-store) + Strimzi operator deployed
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

MANIFESTS_DIR="$PROJECT_ROOT/components/de/iceberg-events/manifests"
NAMESPACE="rook-ceph"
KAFKA_NAMESPACE="iceberg-events"
STRIMZI_NAMESPACE="kafka"

OBC_NAME="iceberg-events"
BUCKET_NAME="iceberg-events"
USER_SECRET="rook-ceph-object-user-s3-store-minio"
S3_ACCESS_KEY="minio"
S3_SECRET_KEY="minio123"

LOCAL_PORT=7482

source "$PROJECT_ROOT/scripts/common/utils.sh"

# Start a port-forward to RGW if not already running
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
    aws configure set default.s3.addressing_style path
}

print_info "Iceberg Events — S3 Notifications → Kafka"
echo "=========================================="

# Pre-flight: check S3 object store exists
if ! kubectl -n "$NAMESPACE" get cephobjectstore s3-store &>/dev/null; then
    print_error "CephObjectStore 's3-store' not found"
    print_info "Deploy Ceph first: ./components/ceph/scripts/build.sh"
    exit 1
fi
print_success "CephObjectStore 's3-store' found"

# Pre-flight: check Strimzi operator is running
if ! kubectl -n "$STRIMZI_NAMESPACE" get deployment strimzi-cluster-operator &>/dev/null; then
    print_error "Strimzi operator not found in namespace '$STRIMZI_NAMESPACE'"
    print_info "Deploy Strimzi first: ./components/events/strimzi/scripts/build.sh"
    exit 1
fi
print_success "Strimzi operator found"

# ============================================================================
# STEP 1: Deploy Kafka cluster (idempotent)
# ============================================================================
print_info "Step 1: Deploying Kafka cluster 'events-kafka'..."
kubectl create namespace "$KAFKA_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f "$MANIFESTS_DIR/kafka-cluster.yaml" -n "$KAFKA_NAMESPACE"

print_info "  Waiting for Kafka cluster to be Ready (up to 3 min)..."
for i in {1..180}; do
    READY=$(kubectl -n "$KAFKA_NAMESPACE" get kafka events-kafka -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")
    if [[ "$READY" == "True" ]]; then
        print_success "  Kafka cluster 'events-kafka' ready"
        break
    fi
    if [[ "$i" -eq 180 ]]; then
        print_error "Kafka cluster not Ready after 180s"
        kubectl -n "$KAFKA_NAMESPACE" get kafka events-kafka -o yaml | tail -20
        exit 1
    fi
    sleep 1
done

# ============================================================================
# STEP 2: Create S3 operating user
# ============================================================================
print_info "Step 2: Creating S3 operating user..."
kubectl apply -f "$MANIFESTS_DIR/s3-user.yaml"

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
# STEP 3: Create bucket via ObjectBucketClaim
# ============================================================================
print_info "Step 3: Creating bucket via ObjectBucketClaim..."
kubectl apply -f "$MANIFESTS_DIR/bucket-claim.yaml"

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

# ============================================================================
# STEP 4: Grant minio user access to bucket via bucket policy
# ============================================================================
print_info "Step 4: Granting minio user access to bucket..."

ensure_port_forward

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
# STEP 5: Create Kafka topic
# ============================================================================
print_info "Step 5: Creating Kafka topic 's3-events'..."
kubectl apply -f "$MANIFESTS_DIR/kafka-topic.yaml"

print_info "  Waiting for topic to be Ready..."
for i in {1..30}; do
    READY=$(kubectl -n "$KAFKA_NAMESPACE" get kafkatopic s3-events -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")
    if [[ "$READY" == "True" ]]; then
        print_success "  KafkaTopic 's3-events' ready"
        break
    fi
    [[ "$i" -eq 30 ]] && { print_warning "KafkaTopic not Ready after 30s (may still be reconciling)"; break; }
    sleep 1
done

# ============================================================================
# STEP 6: Create CephBucketTopic (RGW → Kafka endpoint)
# ============================================================================
print_info "Step 6: Creating CephBucketTopic (RGW → Kafka)..."
kubectl apply -f "$MANIFESTS_DIR/ceph-bucket-topic.yaml"
print_success "  CephBucketTopic 'iceberg-events-topic' applied"

# ============================================================================
# STEP 7: Create CephBucketNotification (event filter)
# ============================================================================
print_info "Step 7: Creating CephBucketNotification..."
kubectl apply -f "$MANIFESTS_DIR/ceph-bucket-notification.yaml"
print_success "  CephBucketNotification 'iceberg-events-notify' applied"

# ============================================================================
# DONE
# ============================================================================
print_success "Iceberg Events Pipeline Ready!"
echo "=========================================="
echo ""
print_info "Bucket:       $BUCKET_NAME"
print_info "Kafka Topic:  s3-events"
print_info "Access Key:   $S3_ACCESS_KEY"
print_info "Secret Key:   $S3_SECRET_KEY"
print_info "S3 Endpoint:  http://localhost:$LOCAL_PORT (port-forward running)"
echo ""
print_info "Test the pipeline:"
echo "  $(dirname "$0")/generate-csv.sh"
echo ""
print_info "Consume events from Kafka:"
echo "  kubectl -n $KAFKA_NAMESPACE run kafka-consumer -ti --rm \\"
echo "    --image=quay.io/strimzi/kafka:0.50.0-kafka-4.1.1 \\"
echo "    --restart=Never -- bin/kafka-console-consumer.sh \\"
echo "    --bootstrap-server events-kafka-kafka-bootstrap:9092 \\"
echo "    --topic s3-events --from-beginning --timeout-ms 10000"
echo ""
print_info "Stop port-forward:"
echo "  pkill -f 'port-forward.*$LOCAL_PORT'"
echo ""
print_info "Destroy:"
echo "  $(dirname "$0")/destroy.sh"
