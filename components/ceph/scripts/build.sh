#!/bin/bash
# Deploy Rook-Ceph to the Kubernetes cluster using Helm
# Run this script from inside the VM
#
# This uses a two-phase installation:
# 1. Install Rook operator (creates CRDs)
# 2. Install Ceph cluster (uses CRDs)
#
# For upgrades: simply re-run this script after modifying values.yaml
# For clean install: ./destroy.sh first, then this script
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

COMPONENT_DIR="$PROJECT_ROOT/components/ceph"
HELM_DIR="$COMPONENT_DIR/helm"

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

print_info "Deploying Rook-Ceph via Helm (two-phase installation)"
print_info "Namespace: $CEPH_NAMESPACE"

# Add Helm repo
print_info "Adding Rook Helm repository..."
helm repo add rook-release "$CEPH_CHART_REPO" 2>/dev/null || true
helm repo update

# Create namespace
kubectl create namespace "$CEPH_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# ============================================================================
# PHASE 1: Install Rook Operator (creates CRDs)
# ============================================================================
print_info "Phase 1: Installing Rook Operator..."

helm upgrade --install rook-ceph-operator rook-release/rook-ceph \
    --namespace "$CEPH_NAMESPACE" \
    --version "$CEPH_CHART_VERSION" \
    --wait --timeout=900s

# Wait for operator to be ready
print_info "Waiting for Rook operator pods to be ready..."
kubectl -n "$CEPH_NAMESPACE" wait --for=condition=Ready pods -l app=rook-ceph-operator --timeout=900s

# Wait for CRDs to be established
print_info "Waiting for Ceph CRDs to be registered..."
kubectl wait --for=condition=Established crd cephclusters.ceph.rook.io --timeout=120s
kubectl wait --for=condition=Established crd cephblockpools.ceph.rook.io --timeout=120s
kubectl wait --for=condition=Established crd cephfilesystems.ceph.rook.io --timeout=120s
kubectl wait --for=condition=Established crd cephobjectstores.ceph.rook.io --timeout=120s

print_success "Phase 1 complete: Operator and CRDs ready"

# ============================================================================
# PHASE 2: Install Ceph Cluster
# ============================================================================
print_info "Phase 2: Installing Ceph Cluster..."

helm upgrade --install rook-ceph-cluster rook-release/rook-ceph-cluster \
    --namespace "$CEPH_NAMESPACE" \
    --version "$CEPH_CHART_VERSION" \
    --values "$HELM_DIR/values.yaml" \
    --set operatorNamespace="$CEPH_NAMESPACE" \
    --wait --timeout=900s

# Wait for cluster health
print_info "Waiting for Ceph cluster to become healthy (may take several minutes)..."
sleep 30  # Give cluster time to start creating resources

# Wait for cluster to be ready (with retries)
for i in {1..20}; do
    PHASE=$(kubectl -n "$CEPH_NAMESPACE" get cephcluster rook-ceph -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
    if [[ "$PHASE" == "Ready" ]]; then
        break
    fi
    print_info "  Cluster phase: $PHASE (waiting... $i/20)"
    sleep 15
done

print_success "Rook-Ceph deployment complete!"
echo ""
print_info "Ceph Status:"
kubectl -n "$CEPH_NAMESPACE" get cephcluster 2>/dev/null || echo "No cluster yet"
echo ""
print_info "Ceph Pods:"
kubectl -n "$CEPH_NAMESPACE" get pods
echo ""
print_info "Storage Classes:"
kubectl get storageclass | grep -E "^NAME|ceph"
echo ""
print_info "Next steps:"
print_info "  - Check status: ./components/ceph/scripts/status.sh"
print_info "  - Test S3: ./components/ceph/scripts/test-s3.sh"
print_info ""
print_info "To upgrade: edit helm/values.yaml and re-run this script"
