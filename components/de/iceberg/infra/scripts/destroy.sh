#!/bin/bash
# Remove Iceberg S3 infrastructure: bucket (OBC) + operating user
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
NAMESPACE="rook-ceph"
OBC_NAME="iceberg-upload"

source "$PROJECT_ROOT/scripts/common/utils.sh"

print_info "Removing Iceberg S3 Infrastructure"
echo "=========================================="

# Delete ObjectBucketClaim (operator removes bucket + OBC secret + configmap)
print_info "Deleting ObjectBucketClaim..."
kubectl delete obc "$OBC_NAME" -n "$NAMESPACE" --ignore-not-found

print_info "Waiting for OBC cleanup..."
kubectl wait --for=delete obc/"$OBC_NAME" -n "$NAMESPACE" --timeout=30s 2>/dev/null || true

# Delete S3 operating user (operator removes its secret)
print_info "Deleting S3 operating user..."
kubectl delete -f "$INFRA_DIR/manifests/s3-user.yaml" --ignore-not-found

print_success "Iceberg S3 Infrastructure Removed!"
