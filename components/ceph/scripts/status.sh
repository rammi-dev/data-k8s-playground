#!/bin/bash
# Quick Ceph health check for daily use
# Run from inside the VM: cd /vagrant && ./components/ceph/scripts/status.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../scripts/common/utils.sh"

print_info "=== Ceph Cluster Health ==="

# Check if rook-ceph namespace exists
if ! kubectl get namespace rook-ceph &>/dev/null; then
    print_error "Ceph not deployed (rook-ceph namespace not found)"
    print_info "Deploy with: ./components/ceph/scripts/build.sh"
    exit 1
fi

# Try to get detailed status from toolbox
echo ""
if kubectl -n rook-ceph get pod -l app=rook-ceph-tools -o name &>/dev/null; then
    print_info "Ceph Status (from toolbox):"
    kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status 2>/dev/null || \
        echo "Toolbox not ready yet"
else
    echo "Toolbox not deployed"
fi

# CephCluster status
echo ""
print_info "CephCluster:"
kubectl -n rook-ceph get cephcluster -o wide 2>/dev/null || echo "No CephCluster found"

# Ceph Pods
echo ""
print_info "Ceph Pods:"
kubectl -n rook-ceph get pods -o wide

# Object Store (S3)
echo ""
print_info "Object Store (S3):"
kubectl -n rook-ceph get cephobjectstore 2>/dev/null || echo "No object store configured"

# Object Store Users
echo ""
print_info "Object Store Users:"
kubectl -n rook-ceph get cephobjectstoreuser 2>/dev/null || echo "No users configured"

# Storage Classes
echo ""
print_info "Ceph Storage Classes:"
kubectl get storageclass | grep -E "^NAME|ceph|rook" || echo "No Ceph storage classes"

print_success "Status check complete!"
