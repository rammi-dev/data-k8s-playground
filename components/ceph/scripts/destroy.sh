#!/bin/bash
# Remove Rook-Ceph from the Kubernetes cluster
# Run this script from inside the VM
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../scripts/common/utils.sh"
source "$SCRIPT_DIR/../../scripts/common/config-loader.sh"

# Check if running inside VM
if ! is_vagrant_vm && [[ ! -f /.dockerenv ]]; then
    print_error "This script should be run inside the Vagrant VM"
    print_info "First SSH into the VM: ./scripts/vagrant/ssh.sh"
    exit 1
fi

print_warning "This will remove Rook-Ceph and all its data!"
read -p "Are you sure? (y/N): " confirm

if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    print_info "Aborted."
    exit 0
fi

print_info "Removing Rook-Ceph..."

# Uninstall Helm release
if helm status rook-ceph -n "$CEPH_NAMESPACE" &>/dev/null; then
    print_info "Uninstalling Helm release..."
    helm uninstall rook-ceph -n "$CEPH_NAMESPACE"
fi

# Delete namespace (this will clean up remaining resources)
if kubectl get namespace "$CEPH_NAMESPACE" &>/dev/null; then
    print_info "Deleting namespace $CEPH_NAMESPACE..."
    kubectl delete namespace "$CEPH_NAMESPACE" --timeout=120s || true
fi

print_success "Rook-Ceph has been removed."
