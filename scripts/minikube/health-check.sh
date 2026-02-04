#!/bin/bash
# Quick cluster and Ceph health verification
# Run from inside the VM: cd /vagrant && ./scripts/minikube/health-check.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common/utils.sh"

print_info "=== Cluster Health Check ==="

# Check minikube status
echo ""
print_info "Minikube Status:"
if minikube status &>/dev/null; then
    minikube status
else
    print_error "Minikube is not running"
    print_info "Start with: ./scripts/minikube/build.sh"
    exit 1
fi

# Check nodes
echo ""
print_info "Nodes:"
kubectl get nodes -o wide --request-timeout=5s 2>/dev/null || {
    print_error "Cannot connect to cluster"
    exit 1
}

# Check system pods
echo ""
print_info "System Pods:"
kubectl get pods -n kube-system --field-selector=status.phase!=Running 2>/dev/null | grep -v "^$" || echo "All system pods running ✅"

# Check enabled addons
echo ""
print_info "Enabled Addons:"
minikube addons list 2>/dev/null | grep enabled | head -10

# Check Ceph if deployed
echo ""
print_info "Ceph Status:"
if kubectl get namespace rook-ceph &>/dev/null; then
    kubectl -n rook-ceph get cephcluster -o wide 2>/dev/null || echo "No CephCluster found"
    echo ""
    kubectl -n rook-ceph get pods --field-selector=status.phase!=Running 2>/dev/null | grep -v "^$" || echo "All Ceph pods running ✅"
else
    echo "Ceph not deployed (rook-ceph namespace not found)"
fi

print_success "Health check complete!"
