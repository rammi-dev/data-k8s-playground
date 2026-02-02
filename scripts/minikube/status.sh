#!/bin/bash
# Check minikube cluster status
# Run this script from inside the VM
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common/utils.sh"
source "$SCRIPT_DIR/../common/config-loader.sh"

# Check if running inside VM
if ! is_vagrant_vm && [[ ! -f /.dockerenv ]]; then
    print_error "This script should be run inside the Vagrant VM"
    print_info "First SSH into the VM: ./scripts/vagrant/ssh.sh"
    exit 1
fi

print_info "Minikube Status:"
echo "----------------"
minikube status || true

echo ""
print_info "Kubernetes Nodes:"
echo "-----------------"
kubectl get nodes 2>/dev/null || print_warning "Cluster not running or not accessible"

echo ""
print_info "All Namespaces:"
echo "---------------"
kubectl get namespaces 2>/dev/null || true

echo ""
print_info "All Pods:"
echo "---------"
kubectl get pods --all-namespaces 2>/dev/null || true
