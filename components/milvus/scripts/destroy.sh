#!/bin/bash
# Uninstall Milvus from the Kubernetes cluster
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

source "$PROJECT_ROOT/scripts/common/utils.sh"
source "$PROJECT_ROOT/scripts/common/config-loader.sh"

if ! kubectl cluster-info &>/dev/null; then
    print_error "Kubernetes cluster is not accessible"
    exit 1
fi

print_warning "This will completely remove Milvus (server + etcd + S3 data + S3 user)!"
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

# Step 3: Delete namespace
print_info "Step 3: Deleting namespace..."
if kubectl get namespace "$MILVUS_NAMESPACE" &>/dev/null; then
    kubectl delete namespace "$MILVUS_NAMESPACE" --timeout=60s 2>/dev/null || true
    print_success "  Namespace deleted"
fi

# Step 4: Delete S3 user from Ceph
print_info "Step 4: Deleting Milvus S3 user..."
kubectl -n "$CEPH_NAMESPACE" delete cephobjectstoreuser milvus --ignore-not-found=true 2>/dev/null || true
print_success "  S3 user deleted"

print_success "Milvus completely removed."
print_info "Note: S3 bucket 'milvus' data remains in Ceph (delete manually if needed)"
print_info "To redeploy: ./components/milvus/scripts/build.sh"
