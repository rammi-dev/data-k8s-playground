#!/bin/bash
# Deploy Rook-Ceph to the Kubernetes cluster using Helm dependencies
# Run this script from inside the VM
#
# For upgrades: simply re-run this script after modifying values.yaml
# For clean install: ./destroy.sh first, then this script
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPONENT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HELM_DIR="$COMPONENT_DIR/helm"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$PROJECT_ROOT/scripts/common/utils.sh"
source "$PROJECT_ROOT/scripts/common/config-loader.sh"

# Check if running inside VM
if ! is_vagrant_vm && [[ ! -f /.dockerenv ]]; then
    print_error "This script should be run inside the Vagrant VM"
    print_info "First SSH into the VM: ./scripts/vagrant/vagrant.sh ssh"
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

print_info "Deploying Rook-Ceph via Helm"
print_info "Namespace: $CEPH_NAMESPACE"
print_info "Chart: $HELM_DIR"

# Add Helm repo (required for dependency resolution)
print_info "Adding Rook Helm repository..."
helm repo add rook-release "$CEPH_CHART_REPO" 2>/dev/null || true
helm repo update

# Create namespace
kubectl create namespace "$CEPH_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Update Helm dependencies (downloads rook-ceph and rook-ceph-cluster charts)
print_info "Updating Helm dependencies..."
cd "$HELM_DIR"
helm dependency update

# Deploy using our umbrella chart
print_info "Installing/Upgrading Rook-Ceph..."
helm upgrade --install rook-ceph-playground . \
    --namespace "$CEPH_NAMESPACE" \
    --values values.yaml \
    --wait --timeout=600s

# Wait for operator to be ready
print_info "Waiting for Rook operator to be ready..."
kubectl -n "$CEPH_NAMESPACE" wait --for=condition=Ready pods -l app=rook-ceph-operator --timeout=300s 2>/dev/null || {
    print_warning "Operator pods not ready yet, continuing..."
}

# Wait for CRDs
print_info "Waiting for Ceph CRDs..."
kubectl wait --for=condition=Established crd cephclusters.ceph.rook.io --timeout=120s 2>/dev/null || true

# Wait for cluster health
print_info "Waiting for Ceph cluster to become healthy (may take several minutes)..."
sleep 30  # Give cluster time to start creating resources
kubectl -n "$CEPH_NAMESPACE" wait --for=jsonpath='{.status.phase}'=Ready cephcluster/rook-ceph --timeout=600s 2>/dev/null || {
    print_warning "Cluster not fully ready yet, but deployment continues"
}

print_success "Rook-Ceph deployment complete!"
echo ""
print_info "Ceph Status:"
kubectl -n "$CEPH_NAMESPACE" get cephcluster 2>/dev/null || echo "No cluster yet"
echo ""
print_info "Ceph Pods:"
kubectl -n "$CEPH_NAMESPACE" get pods
echo ""
print_info "Next steps:"
print_info "  - Check status: ./components/ceph/scripts/status.sh"
print_info "  - Test S3: ./components/ceph/scripts/test-s3.sh"
print_info ""
print_info "To upgrade: edit helm/values.yaml and re-run this script"


