#!/bin/bash
# Deploy Rook-Ceph to the Kubernetes cluster
# Run this script from inside the VM
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPONENT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/../../scripts/common/utils.sh"
source "$SCRIPT_DIR/../../scripts/common/config-loader.sh"

# Check if running inside VM
if ! is_vagrant_vm && [[ ! -f /.dockerenv ]]; then
    print_error "This script should be run inside the Vagrant VM"
    print_info "First SSH into the VM: ./scripts/vagrant/ssh.sh"
    exit 1
fi

# Check if component is enabled
if [[ "$CEPH_ENABLED" != "true" ]]; then
    print_error "Ceph is not enabled in config.yaml"
    print_info "Set 'components.ceph.enabled: true' in config.yaml"
    exit 1
fi

# Check if minikube is running
if ! minikube status &>/dev/null; then
    print_error "Minikube is not running"
    print_info "Start minikube first: ./scripts/minikube/build.sh"
    exit 1
fi

print_info "Deploying Rook-Ceph"
print_info "Namespace: $CEPH_NAMESPACE"
print_info "Chart Version: $CEPH_CHART_VERSION"

# Add Helm repo
print_info "Adding Rook Helm repository..."
helm repo add rook-release "$CEPH_CHART_REPO" || true
helm repo update

# Create namespace
kubectl create namespace "$CEPH_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Install Rook-Ceph operator
print_info "Installing Rook-Ceph operator..."
helm upgrade --install rook-ceph rook-release/rook-ceph \
    --namespace "$CEPH_NAMESPACE" \
    --version "$CEPH_CHART_VERSION" \
    --values "$COMPONENT_DIR/helm/values.yaml" \
    --wait

# Wait for operator to be ready
print_info "Waiting for Rook operator to be ready..."
kubectl -n "$CEPH_NAMESPACE" wait --for=condition=Ready pods -l app=rook-ceph-operator --timeout=300s

print_success "Rook-Ceph operator deployed!"
print_info "Note: You still need to create a CephCluster CR to provision storage"
print_info "See: https://rook.io/docs/rook/latest/CRDs/Cluster/ceph-cluster-crd/"
