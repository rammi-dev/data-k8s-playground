#!/bin/bash
# Uninstall Milvus from the Kubernetes cluster
# Usage:
#   ./destroy.sh              # Full cleanup including S3 bucket data
#   ./destroy.sh --keep-data  # Keep S3 bucket data for redeployment
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

source "$PROJECT_ROOT/scripts/common/utils.sh"
source "$PROJECT_ROOT/scripts/common/config-loader.sh"

KEEP_DATA=false
if [[ "${1:-}" == "--keep-data" ]]; then
    KEEP_DATA=true
fi

if ! kubectl cluster-info &>/dev/null; then
    print_error "Kubernetes cluster is not accessible"
    exit 1
fi

if [[ "$KEEP_DATA" == "true" ]]; then
    print_warning "This will remove Milvus but KEEP S3 bucket data."
else
    print_warning "This will completely remove Milvus INCLUDING all S3 bucket data!"
    print_warning "To keep S3 data, use: ./destroy.sh --keep-data"
fi
read -p "Are you sure? (y/N): " confirm

if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    print_info "Aborted."
    exit 0
fi

print_info "Removing Milvus..."
echo "=========================================="

# Step 1: Uninstall Helm release
print_info "Step 1: Uninstalling Helm release..."
if helm status milvus -n "$MILVUS_NAMESPACE" &>/dev/null; then
    helm uninstall milvus -n "$MILVUS_NAMESPACE" --timeout=120s 2>/dev/null || true
    print_success "  Helm release uninstalled"
else
    print_info "  Helm release not found, skipping"
fi

# Step 2: Delete PVCs
print_info "Step 2: Deleting PVCs..."
kubectl -n "$MILVUS_NAMESPACE" delete pvc --all --timeout=60s 2>/dev/null || true
print_success "  PVCs deleted"

# Step 3: Delete S3 bucket data (unless --keep-data)
if [[ "$KEEP_DATA" == "false" ]]; then
    print_info "Step 3: Deleting S3 bucket data..."
    S3_SECRET="rook-ceph-object-user-s3-store-milvus"
    if kubectl -n "$CEPH_NAMESPACE" get secret "$S3_SECRET" &>/dev/null; then
        S3_ACCESS_KEY=$(kubectl -n "$CEPH_NAMESPACE" get secret "$S3_SECRET" \
            -o jsonpath='{.data.AccessKey}' | base64 -d)
        S3_SECRET_KEY=$(kubectl -n "$CEPH_NAMESPACE" get secret "$S3_SECRET" \
            -o jsonpath='{.data.SecretKey}' | base64 -d)

        kubectl -n "$CEPH_NAMESPACE" exec deploy/rook-ceph-tools -- bash -c "
            export AWS_ACCESS_KEY_ID='$S3_ACCESS_KEY'
            export AWS_SECRET_ACCESS_KEY='$S3_SECRET_KEY'
            export AWS_DEFAULT_REGION='us-east-1'
            RGW=http://rook-ceph-rgw-s3-store.$CEPH_NAMESPACE.svc:80
            aws --endpoint-url \$RGW s3 rb s3://milvus --force 2>/dev/null && echo 'Bucket deleted' || echo 'Bucket not found or already empty'
        " 2>/dev/null || print_warning "  Could not delete bucket (may need manual cleanup)"
        print_success "  S3 bucket data deleted"
    else
        print_info "  S3 credentials not found, skipping bucket cleanup"
    fi
else
    print_info "Step 3: Skipping S3 bucket data deletion (--keep-data)"
fi

# Step 4: Delete S3 user from Ceph
print_info "Step 4: Deleting Milvus S3 user..."
kubectl -n "$CEPH_NAMESPACE" delete cephobjectstoreuser milvus --ignore-not-found=true 2>/dev/null || true
print_success "  S3 user deleted"

# Step 5: Delete namespace
print_info "Step 5: Deleting namespace..."
if kubectl get namespace "$MILVUS_NAMESPACE" &>/dev/null; then
    kubectl delete namespace "$MILVUS_NAMESPACE" --timeout=60s 2>/dev/null || true
    print_success "  Namespace deleted"
fi

print_success "Milvus completely removed."
print_info "To redeploy: ./components/milvus/scripts/build.sh"
