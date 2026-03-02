#!/bin/bash
# Remove iceberg-events: notifications, topic, bucket, user, Kafka cluster
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
KAFKA_NAMESPACE="iceberg-events"
OBC_NAME="iceberg-events"

source "$PROJECT_ROOT/scripts/common/utils.sh"

print_info "Removing Iceberg Events Pipeline"
echo "=========================================="

# Kill any port-forward on 7482
if ss -tlnp 2>/dev/null | grep -q ":7482 "; then
    print_info "Stopping port-forward on :7482..."
    pkill -f 'port-forward.*7482' 2>/dev/null || true
fi

# 1. CephBucketNotification
print_info "Deleting CephBucketNotification..."
kubectl delete cephbucketnotification iceberg-events-notify -n "$NAMESPACE" --ignore-not-found

# 2. CephBucketTopic
print_info "Deleting CephBucketTopic..."
kubectl delete cephbuckettopic iceberg-events-topic -n "$NAMESPACE" --ignore-not-found

# 3. KafkaTopic
print_info "Deleting KafkaTopic..."
kubectl delete kafkatopic s3-events -n "$KAFKA_NAMESPACE" --ignore-not-found

# 4. ObjectBucketClaim (operator removes bucket + auto-secrets)
print_info "Deleting ObjectBucketClaim..."
kubectl delete obc "$OBC_NAME" -n "$NAMESPACE" --ignore-not-found
print_info "  Waiting for OBC cleanup..."
kubectl wait --for=delete obc/"$OBC_NAME" -n "$NAMESPACE" --timeout=30s 2>/dev/null || true

# 5. CephObjectStoreUser — delete BEFORE keys secret (rook issue #16007)
print_info "Deleting CephObjectStoreUser..."
kubectl delete cephobjectstoreuser minio -n "$NAMESPACE" --ignore-not-found
print_info "  Waiting for user cleanup..."
kubectl wait --for=delete cephobjectstoreuser/minio -n "$NAMESPACE" --timeout=30s 2>/dev/null || true

# 6. Credentials secret
print_info "Deleting credentials secret..."
kubectl delete secret iceberg-events-s3-keys -n "$NAMESPACE" --ignore-not-found

# 7. Kafka cluster
print_info "Deleting Kafka cluster 'events-kafka'..."
kubectl delete kafka events-kafka -n "$KAFKA_NAMESPACE" --ignore-not-found
kubectl delete kafkanodepool dual-role -n "$KAFKA_NAMESPACE" --ignore-not-found
print_info "  Waiting for Kafka cluster cleanup..."
kubectl wait --for=delete kafka/events-kafka -n "$KAFKA_NAMESPACE" --timeout=60s 2>/dev/null || true

# 8. Namespace
print_info "Deleting namespace '$KAFKA_NAMESPACE'..."
kubectl delete namespace "$KAFKA_NAMESPACE" --ignore-not-found

print_success "Iceberg Events Pipeline Removed!"
