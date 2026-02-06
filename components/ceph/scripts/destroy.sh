#!/bin/bash
# Remove Rook-Ceph from the Kubernetes cluster
# Run this script from inside the VM
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

# Check if running inside VM
if ! is_vagrant_vm && [[ ! -f /.dockerenv ]]; then
    print_error "This script should be run inside the Vagrant VM"
    print_info "First SSH into the VM: ./scripts/vagrant/vagrant.sh ssh"
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

# Delete namespace (this will clean up remaining resources)
if kubectl get namespace "$CEPH_NAMESPACE" &>/dev/null; then
    print_info "Deleting namespace $CEPH_NAMESPACE..."
    kubectl delete namespace "$CEPH_NAMESPACE" --timeout=120s || true
fi

# Clean up Rook data on nodes
print_info "Cleaning up Rook data on nodes..."
for node in $(kubectl get nodes -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
    minikube ssh -n "$node" "sudo rm -rf /var/lib/rook" 2>/dev/null || true
done

print_success "Rook-Ceph has been removed."
