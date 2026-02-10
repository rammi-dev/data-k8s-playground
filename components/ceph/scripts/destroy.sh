#!/bin/bash
# Remove Rook-Ceph from the Kubernetes cluster
# Works from WSL with Hyper-V minikube or inside Vagrant VM
set -e

# Determine project root (works from any location)
if [[ -d "/vagrant" ]]; then
    PROJECT_ROOT="/vagrant"
elif [[ -n "${PROJECT_ROOT:-}" ]]; then
    : # Use existing PROJECT_ROOT
else
    # Fallback: calculate from script location
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
fi

source "$PROJECT_ROOT/scripts/common/utils.sh"
source "$PROJECT_ROOT/scripts/common/config-loader.sh"

# Check if Kubernetes cluster is accessible
if ! kubectl cluster-info &>/dev/null; then
    print_error "Kubernetes cluster is not accessible"
    exit 1
fi

print_warning "This will remove Rook-Ceph and all its data!"
read -p "Are you sure? (y/N): " confirm

if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    print_info "Aborted."
    exit 0
fi

print_info "Removing Rook-Ceph..."

# Uninstall Helm releases (both operator and cluster)
for release in rook-ceph-cluster rook-ceph-operator rook-ceph-playground; do
    if helm status "$release" -n "$CEPH_NAMESPACE" &>/dev/null; then
        print_info "Uninstalling Helm release: $release..."
        helm uninstall "$release" -n "$CEPH_NAMESPACE" --wait || true
    fi
done

# Clean up any remaining Ceph resources
print_info "Cleaning up Ceph resources..."
kubectl -n "$CEPH_NAMESPACE" delete cephcluster --all --timeout=60s 2>/dev/null || true
kubectl -n "$CEPH_NAMESPACE" delete cephblockpool --all --timeout=60s 2>/dev/null || true
kubectl -n "$CEPH_NAMESPACE" delete cephfilesystem --all --timeout=60s 2>/dev/null || true
kubectl -n "$CEPH_NAMESPACE" delete cephobjectstore --all --timeout=60s 2>/dev/null || true

# Delete OSD PVCs (used by PVC-based storage)
print_info "Deleting OSD PVCs..."
kubectl -n "$CEPH_NAMESPACE" delete pvc -l app=rook-ceph-osd --timeout=60s 2>/dev/null || true
kubectl -n "$CEPH_NAMESPACE" delete pvc --all --timeout=60s 2>/dev/null || true

# Delete Ceph StorageClasses
print_info "Deleting Ceph StorageClasses..."
kubectl delete storageclass ceph-block ceph-filesystem ceph-bucket 2>/dev/null || true

# Delete namespace (this will clean up remaining resources)
if kubectl get namespace "$CEPH_NAMESPACE" &>/dev/null; then
    print_info "Deleting namespace $CEPH_NAMESPACE..."
    kubectl delete namespace "$CEPH_NAMESPACE" --timeout=120s || true
fi

# Remove finalizers from stuck resources if namespace deletion hangs
if kubectl get namespace "$CEPH_NAMESPACE" &>/dev/null; then
    print_warning "Namespace stuck, removing finalizers..."
    kubectl get cephcluster -n "$CEPH_NAMESPACE" -o name 2>/dev/null | while read obj; do
        kubectl patch "$obj" -n "$CEPH_NAMESPACE" -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
    done
    kubectl delete namespace "$CEPH_NAMESPACE" --force --grace-period=0 2>/dev/null || true
fi

# Clean up Rook data on nodes (if minikube is accessible)
if command -v minikube &>/dev/null && minikube status &>/dev/null; then
    print_info "Cleaning up Rook data on minikube nodes..."
    for node in $(kubectl get nodes -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
        minikube ssh -n "$node" "sudo rm -rf /var/lib/rook" 2>/dev/null || true
    done
fi

# Delete any remaining CRDs (optional, for full cleanup)
print_info "Cleaning up Ceph CRDs..."
kubectl delete crd -l app.kubernetes.io/part-of=rook-ceph 2>/dev/null || true

print_success "Rook-Ceph has been removed."
print_info "Note: Run 'kubectl get pv' to verify no orphaned PVs remain."
