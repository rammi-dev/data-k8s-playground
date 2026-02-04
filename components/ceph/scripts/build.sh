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

# Wait for CRDs to be established
print_info "Waiting for Ceph CRDs to be established..."
kubectl wait --for=condition=Established crd cephclusters.ceph.rook.io --timeout=60s
kubectl wait --for=condition=Established crd cephobjectstores.ceph.rook.io --timeout=60s

# Deploy CephCluster and components via rook-ceph-cluster chart
print_info "Deploying CephCluster..."
helm upgrade --install rook-ceph-cluster rook-release/rook-ceph-cluster \
    --namespace "$CEPH_NAMESPACE" \
    --version "$CEPH_CHART_VERSION" \
    --values "$COMPONENT_DIR/helm/values.yaml" \
    --set operatorNamespace="$CEPH_NAMESPACE" \
    --wait --timeout=600s

# Wait for Ceph cluster to become healthy
print_info "Waiting for Ceph cluster to become healthy (this may take several minutes)..."
kubectl -n "$CEPH_NAMESPACE" wait --for=jsonpath='{.status.phase}'=Ready cephcluster/rook-ceph --timeout=600s 2>/dev/null || {
    print_warning "Cluster not fully ready yet, but pods should be starting"
}

# Deploy toolbox for debugging
print_info "Deploying Ceph toolbox..."
kubectl -n "$CEPH_NAMESPACE" apply -f https://raw.githubusercontent.com/rook/rook/release-1.13/deploy/examples/toolbox.yaml 2>/dev/null || true
kubectl -n "$CEPH_NAMESPACE" wait --for=condition=Ready pods -l app=rook-ceph-tools --timeout=120s 2>/dev/null || true

print_success "Rook-Ceph cluster deployed!"
echo ""
print_info "Ceph Status:"
kubectl -n "$CEPH_NAMESPACE" get cephcluster
echo ""
print_info "Ceph Pods:"
kubectl -n "$CEPH_NAMESPACE" get pods
echo ""
print_info "Next steps:"
print_info "  - Check status: ./components/ceph/scripts/status.sh"
print_info "  - Test S3: ./components/ceph/scripts/test-s3.sh"

