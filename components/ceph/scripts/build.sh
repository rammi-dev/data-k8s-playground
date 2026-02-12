#!/bin/bash
# Deploy Rook-Ceph operator via Helm
# After this, run create-cluster.sh to apply the cluster CRDs
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
COMPONENT_DIR="$PROJECT_ROOT/components/ceph"

source "$PROJECT_ROOT/scripts/common/utils.sh"
source "$PROJECT_ROOT/scripts/common/config-loader.sh"

# Check if component is enabled
if [[ "$CEPH_ENABLED" != "true" ]]; then
    print_error "Ceph is not enabled in config.yaml"
    print_info "Set 'components.ceph.enabled: true' in config.yaml"
    exit 1
fi

# Check if Kubernetes cluster is accessible
if ! kubectl cluster-info &>/dev/null; then
    print_error "Kubernetes cluster is not accessible"
    exit 1
fi

print_info "Deploying Rook-Ceph Operator (${CEPH_CHART_VERSION})"
print_info "Namespace: $CEPH_NAMESPACE"
echo "=========================================="

# ============================================================================
# STEP 1: Add Helm repo and create namespace
# ============================================================================
print_info "Step 1: Setting up Helm repo and namespace..."
helm repo add rook-release "$CEPH_CHART_REPO" 2>/dev/null || true
helm repo update
kubectl create namespace "$CEPH_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
print_success "  Namespace $CEPH_NAMESPACE ready"

# ============================================================================
# STEP 2: Install Rook Operator via Helm
# ============================================================================
print_info "Step 2: Installing Rook Operator..."

helm upgrade --install rook-ceph-operator rook-release/rook-ceph \
    --namespace "$CEPH_NAMESPACE" \
    --version "$CEPH_CHART_VERSION" \
    --wait --timeout=900s

print_info "  Waiting for operator pod..."
kubectl -n "$CEPH_NAMESPACE" wait --for=condition=Ready pods \
    -l app=rook-ceph-operator --timeout=900s

print_success "  Rook Operator deployed"

# ============================================================================
# STEP 3: Wait for CRDs to be established
# ============================================================================
print_info "Step 3: Waiting for CRDs..."
for crd in cephclusters.ceph.rook.io cephblockpools.ceph.rook.io \
           cephfilesystems.ceph.rook.io cephobjectstores.ceph.rook.io; do
    kubectl wait --for=condition=Established crd "$crd" --timeout=120s
done
print_success "  CRDs established"

# ============================================================================
# STEP 4: Clean stale MON state (if any from previous cluster)
# ============================================================================
if kubectl -n "$CEPH_NAMESPACE" get cm rook-ceph-mon-endpoints &>/dev/null; then
    MON_PODS=$(kubectl -n "$CEPH_NAMESPACE" get pods -l app=rook-ceph-mon --no-headers 2>/dev/null | wc -l)
    if [[ "$MON_PODS" -eq 0 ]]; then
        print_warning "Found stale mon state from previous cluster, cleaning up..."
        kubectl -n "$CEPH_NAMESPACE" scale deploy/rook-ceph-operator --replicas=0
        kubectl -n "$CEPH_NAMESPACE" wait --for=delete pod -l app=rook-ceph-operator --timeout=60s 2>/dev/null || true
        for obj in secret/rook-ceph-mon secret/rook-ceph-config \
                   cm/rook-ceph-mon-endpoints cm/rook-ceph-csi-config \
                   cm/rook-ceph-csi-mapping-config cm/rook-ceph-pdbstatemap; do
            kubectl -n "$CEPH_NAMESPACE" patch "$obj" --type merge -p '{"metadata":{"finalizers":null}}' 2>/dev/null || true
            kubectl -n "$CEPH_NAMESPACE" delete "$obj" --timeout=10s 2>/dev/null || true
        done
        kubectl -n "$CEPH_NAMESPACE" scale deploy/rook-ceph-operator --replicas=1
        kubectl -n "$CEPH_NAMESPACE" wait --for=condition=Ready pods -l app=rook-ceph-operator --timeout=120s
        print_success "  Stale state cleaned, operator restarted"
    fi
fi

# ============================================================================
# DONE
# ============================================================================
print_success "Rook-Ceph Operator deployed!"
echo "=========================================="
echo ""
print_info "Operator Pods:"
kubectl -n "$CEPH_NAMESPACE" get pods
echo ""
print_info "Next steps:"
print_info "  1. Create cluster:  ./components/ceph/scripts/create-cluster.sh"
print_info "  2. Check status:    ./components/ceph/scripts/status.sh"
