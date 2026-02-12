#!/bin/bash
# Create Ceph cluster by applying CRD manifests
# Requires: Rook operator deployed (build.sh)
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
COMPONENT_DIR="$PROJECT_ROOT/components/ceph"

source "$PROJECT_ROOT/scripts/common/utils.sh"
source "$PROJECT_ROOT/scripts/common/config-loader.sh"

# Check if Kubernetes cluster is accessible
if ! kubectl cluster-info &>/dev/null; then
    print_error "Kubernetes cluster is not accessible"
    exit 1
fi

# Check if operator is running
if ! kubectl -n "$CEPH_NAMESPACE" get deploy rook-ceph-operator &>/dev/null; then
    print_error "Rook operator not found in $CEPH_NAMESPACE"
    print_info "Deploy operator first: ./components/ceph/scripts/build.sh"
    exit 1
fi

print_info "Creating Ceph Cluster"
print_info "Namespace: $CEPH_NAMESPACE"
echo "=========================================="

# ============================================================================
# STEP 1: Apply cluster CRD manifests
# ============================================================================
print_info "Step 1: Applying cluster manifests..."
kubectl apply -R -f "$COMPONENT_DIR/manifests/" -n "$CEPH_NAMESPACE"
print_success "  Manifests applied"

# ============================================================================
# STEP 2: Wait for cluster to be ready
# ============================================================================
print_info "Step 2: Waiting for Ceph cluster to become healthy (may take several minutes)..."
sleep 30

for i in {1..20}; do
    PHASE=$(kubectl -n "$CEPH_NAMESPACE" get cephcluster rook-ceph -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
    if [[ "$PHASE" == "Ready" ]]; then
        print_success "  Cluster phase: Ready"
        break
    fi
    print_info "  Cluster phase: $PHASE (waiting... $i/20)"
    [[ "$i" -eq 20 ]] && print_warning "  Cluster not Ready after 5 minutes"
    sleep 15
done

# ============================================================================
# STEP 3: Wait for OSDs
# ============================================================================
print_info "Step 3: Waiting for OSDs (up to 120s)..."
OSD_OK=false
for i in {1..24}; do
    sleep 5
    OSD_COUNT=$(kubectl -n "$CEPH_NAMESPACE" exec deploy/rook-ceph-tools -- \
        ceph osd stat --format json 2>/dev/null | \
        python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('num_up_osds', d.get('num_up', 0)))" 2>/dev/null || echo "0")
    if [[ "$OSD_COUNT" -gt 0 ]]; then
        print_success "  $OSD_COUNT OSD(s) are up"
        OSD_OK=true
        break
    fi
    if [[ "$i" -eq 12 ]]; then
        PREPARE_ISSUES=$(kubectl -n "$CEPH_NAMESPACE" logs -l app=rook-ceph-osd-prepare --tail=5 2>/dev/null | grep -c "different ceph cluster" || true)
        if [[ "$PREPARE_ISSUES" -gt 0 ]]; then
            print_error "Disks have bluestore data from a previous cluster!"
            print_info "Run: ./components/ceph/scripts/destroy.sh cluster"
            exit 1
        fi
    fi
    print_info "  Waiting for OSDs... ($i/24)"
done

if [[ "$OSD_OK" == "false" ]]; then
    print_error "No OSDs came up after 120s"
    print_info "Check OSD prepare logs:"
    print_info "  kubectl -n $CEPH_NAMESPACE logs -l app=rook-ceph-osd-prepare --tail=20"
    exit 1
fi

# ============================================================================
# STEP 4: Wait for S3 object store
# ============================================================================
print_info "Step 4: Waiting for S3 object store..."
for i in {1..20}; do
    S3_PHASE=$(kubectl -n "$CEPH_NAMESPACE" get cephobjectstore s3-store -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
    if [[ "$S3_PHASE" == "Ready" ]]; then
        print_success "  S3 object store is ready"
        break
    fi
    [[ "$i" -eq 20 ]] && print_warning "  S3 still $S3_PHASE after 5m (may need more time)"
    print_info "  S3 phase: $S3_PHASE ($i/20)"
    sleep 15
done

# ============================================================================
# STEP 5: Wait for S3 admin user secret
# ============================================================================
print_info "Step 5: Waiting for S3 admin user secret..."
for i in {1..12}; do
    if kubectl -n "$CEPH_NAMESPACE" get secret rook-ceph-object-user-s3-store-admin &>/dev/null; then
        print_success "  S3 admin user ready"
        break
    fi
    [[ "$i" -eq 12 ]] && print_warning "  Admin user secret not ready after 60s"
    sleep 5
done

# ============================================================================
# DONE
# ============================================================================
print_success "Ceph Cluster created!"
echo "=========================================="
echo ""
print_info "Ceph Status:"
kubectl -n "$CEPH_NAMESPACE" exec deploy/rook-ceph-tools -- ceph status 2>/dev/null || echo "Could not get status"
echo ""
print_info "Storage Classes:"
kubectl get storageclass | grep -E "^NAME|ceph"
echo ""
print_info "Next steps:"
print_info "  - Check status:       ./components/ceph/scripts/status.sh"
print_info "  - Test S3:            ./components/ceph/scripts/test/test-s3.sh"
print_info "  - Test block storage: ./components/ceph/scripts/test/test-block-storage.sh"
