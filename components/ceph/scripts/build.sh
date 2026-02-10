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

# Check if running inside VM (only enforced if REQUIRE_VM=1)
if [[ "${REQUIRE_VM:-}" == "1" ]] && ! is_vagrant_vm && [[ ! -f /.dockerenv ]]; then
    print_error "This script must be run inside the Vagrant VM (REQUIRE_VM=1 is set)"
    print_info "First SSH into the VM: ./scripts/vagrant/vagrant.sh ssh"
    exit 1
fi

# Check if component is enabled
if [[ "$CEPH_ENABLED" != "true" ]]; then
    print_error "Ceph is not enabled in config.yaml"
    print_info "Set 'components.ceph.enabled: true' in config.yaml"
    exit 1
fi

# Check if Kubernetes cluster is accessible
if ! kubectl cluster-info &>/dev/null; then
    print_error "Kubernetes cluster is not accessible"
    print_info "Make sure kubectl is configured and the cluster is running"
    print_info "  - From Vagrant VM: ./scripts/minikube/build.sh"
    print_info "  - From WSL with Windows minikube: run setup-kubeconfig.sh first"
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
# CLEANUP: Remove stale state from previous cluster (if any)
# ============================================================================
# The operator creates configmaps/secrets for mon endpoints that persist across
# helm uninstall/reinstall. If stale, the operator gets stuck trying to connect
# to a dead mon instead of creating a new one.
if kubectl -n "$CEPH_NAMESPACE" get cm rook-ceph-mon-endpoints &>/dev/null; then
    # Check if a mon pod actually exists
    MON_PODS=$(kubectl -n "$CEPH_NAMESPACE" get pods -l app=rook-ceph-mon --no-headers 2>/dev/null | wc -l)
    if [[ "$MON_PODS" -eq 0 ]]; then
        print_warning "Found stale mon state from previous cluster, cleaning up..."
        # Scale down operator first so it doesn't recreate state while we delete it
        kubectl -n "$CEPH_NAMESPACE" scale deploy/rook-ceph-operator --replicas=0
        kubectl -n "$CEPH_NAMESPACE" wait --for=delete pod -l app=rook-ceph-operator --timeout=60s 2>/dev/null || true
        # Delete stale state (remove finalizers first - secrets may have disaster-protection)
        for obj in secret/rook-ceph-mon secret/rook-ceph-config cm/rook-ceph-mon-endpoints cm/rook-ceph-csi-config cm/rook-ceph-csi-mapping-config cm/rook-ceph-pdbstatemap; do
            kubectl -n "$CEPH_NAMESPACE" patch "$obj" --type merge -p '{"metadata":{"finalizers":null}}' 2>/dev/null || true
            kubectl -n "$CEPH_NAMESPACE" delete "$obj" --timeout=10s 2>/dev/null || true
        done
        # Scale operator back up with clean state
        kubectl -n "$CEPH_NAMESPACE" scale deploy/rook-ceph-operator --replicas=1
        kubectl -n "$CEPH_NAMESPACE" wait --for=condition=Ready pods -l app=rook-ceph-operator --timeout=120s
        print_success "Stale state cleaned, operator restarted"
    fi
fi

# ============================================================================
# PHASE 2: Install Ceph Cluster
# ============================================================================
print_info "Phase 2: Installing Ceph Cluster..."

helm upgrade --install rook-ceph-cluster rook-release/rook-ceph-cluster \
    --namespace "$CEPH_NAMESPACE" \
    --version "$CEPH_CHART_VERSION" \
    --values "$HELM_DIR/cluster-values.yaml" \
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

# Wait for OSDs to come up (critical - no OSDs means no storage)
print_info "Waiting for OSDs to start (up to 120s)..."
OSD_OK=false
for i in {1..24}; do
    sleep 5
    OSD_COUNT=$(kubectl -n "$CEPH_NAMESPACE" exec deploy/rook-ceph-tools -- ceph osd stat --format json 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('num_up',0))" 2>/dev/null || echo "0")
    if [[ "$OSD_COUNT" -gt 0 ]]; then
        print_success "  $OSD_COUNT OSD(s) are up"
        OSD_OK=true
        break
    fi
    # Check if prepare jobs found issues
    if [[ "$i" -eq 12 ]]; then
        PREPARE_ISSUES=$(kubectl -n "$CEPH_NAMESPACE" logs -l app=rook-ceph-osd-prepare --tail=5 2>/dev/null | grep -c "different ceph cluster" || true)
        if [[ "$PREPARE_ISSUES" -gt 0 ]]; then
            print_error "Disks have bluestore data from a previous cluster!"
            print_info "Run: ./components/ceph/scripts/destroy.sh && ./components/ceph/scripts/build.sh"
            exit 1
        fi
    fi
    print_info "  Waiting for OSDs... ($i/24)"
done

if [[ "$OSD_OK" == "false" ]]; then
    print_error "No OSDs came up after 120s"
    print_info "Check OSD prepare logs:"
    print_info "  kubectl -n $CEPH_NAMESPACE logs -l app=rook-ceph-osd-prepare --tail=20"
    print_info ""
    print_info "If disks have old data, run destroy.sh first (it zaps disks):"
    print_info "  ./components/ceph/scripts/destroy.sh && ./components/ceph/scripts/build.sh"
    exit 1
fi

# Wait for S3 object store to become ready
print_info "Waiting for S3 object store..."
for i in {1..20}; do
    S3_PHASE=$(kubectl -n "$CEPH_NAMESPACE" get cephobjectstore s3-store -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
    if [[ "$S3_PHASE" == "Ready" ]]; then
        print_success "  S3 object store is ready"
        break
    fi
    if [[ "$i" -eq 20 ]]; then
        print_warning "  S3 still $S3_PHASE after 5m (may need more time)"
    else
        print_info "  S3 phase: $S3_PHASE ($i/20)"
    fi
    sleep 15
done

print_success "Rook-Ceph deployment complete!"
echo ""
print_info "Ceph Status:"
kubectl -n "$CEPH_NAMESPACE" exec deploy/rook-ceph-tools -- ceph status 2>/dev/null || echo "Could not get status"
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
