#!/bin/bash
# Gracefully shut down Ceph before minikube stop
# Run from WSL: ./components/ceph/scripts/pre-stop.sh
# Then: minikube stop (from PowerShell)
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$PROJECT_ROOT/scripts/common/utils.sh"
source "$PROJECT_ROOT/scripts/common/config-loader.sh"

if ! kubectl cluster-info &>/dev/null; then
    print_error "Kubernetes cluster is not accessible"
    exit 1
fi

print_info "=== Graceful Ceph Shutdown ==="

# Step 1: Set OSD noout flag to prevent rebalancing during shutdown
print_info "Step 1: Setting OSD noout flag..."
kubectl -n "$CEPH_NAMESPACE" exec deploy/rook-ceph-tools -- ceph osd set noout 2>/dev/null || true

# Step 2: Wait for any ongoing recovery to complete
print_info "Step 2: Checking for ongoing recovery..."
for i in {1..10}; do
    RECOVERING=$(kubectl -n "$CEPH_NAMESPACE" exec deploy/rook-ceph-tools -- ceph status 2>/dev/null | grep -c "recovering\|backfill\|degraded" || true)
    if [[ "$RECOVERING" -eq 0 ]]; then
        break
    fi
    print_info "  Recovery in progress, waiting... ($i/10)"
    sleep 5
done

# Step 3: Flush OSD journals
print_info "Step 3: Flushing OSD journals..."
OSD_IDS=$(kubectl -n "$CEPH_NAMESPACE" exec deploy/rook-ceph-tools -- ceph osd ls 2>/dev/null || true)
for osd_id in $OSD_IDS; do
    kubectl -n "$CEPH_NAMESPACE" exec deploy/rook-ceph-tools -- ceph tell osd.$osd_id flush_pg_stats 2>/dev/null || true
done

# Step 4: Scale down services in order (RGW -> MDS -> OSD -> MGR)
print_info "Step 4: Scaling down Ceph services..."

# Scale down RGW (S3 gateway)
for deploy in $(kubectl -n "$CEPH_NAMESPACE" get deploy -l app=rook-ceph-rgw -o name 2>/dev/null); do
    print_info "  Scaling down $deploy..."
    kubectl -n "$CEPH_NAMESPACE" scale "$deploy" --replicas=0 2>/dev/null || true
done

# Scale down MDS (filesystem)
for deploy in $(kubectl -n "$CEPH_NAMESPACE" get deploy -l app=rook-ceph-mds -o name 2>/dev/null); do
    print_info "  Scaling down $deploy..."
    kubectl -n "$CEPH_NAMESPACE" scale "$deploy" --replicas=0 2>/dev/null || true
done

# Scale down exporters
for deploy in $(kubectl -n "$CEPH_NAMESPACE" get deploy -l app=rook-ceph-exporter -o name 2>/dev/null); do
    kubectl -n "$CEPH_NAMESPACE" scale "$deploy" --replicas=0 2>/dev/null || true
done

# Scale down OSD
for deploy in $(kubectl -n "$CEPH_NAMESPACE" get deploy -l app=rook-ceph-osd -o name 2>/dev/null); do
    print_info "  Scaling down $deploy..."
    kubectl -n "$CEPH_NAMESPACE" scale "$deploy" --replicas=0 2>/dev/null || true
done

# Wait for OSDs to stop
print_info "  Waiting for OSDs to stop..."
kubectl -n "$CEPH_NAMESPACE" wait --for=delete pod -l app=rook-ceph-osd --timeout=60s 2>/dev/null || true

# Scale down MGR
for deploy in $(kubectl -n "$CEPH_NAMESPACE" get deploy -l app=rook-ceph-mgr -o name 2>/dev/null); do
    print_info "  Scaling down $deploy..."
    kubectl -n "$CEPH_NAMESPACE" scale "$deploy" --replicas=0 2>/dev/null || true
done

# Scale down MON
for deploy in $(kubectl -n "$CEPH_NAMESPACE" get deploy -l app=rook-ceph-mon -o name 2>/dev/null); do
    print_info "  Scaling down $deploy..."
    kubectl -n "$CEPH_NAMESPACE" scale "$deploy" --replicas=0 2>/dev/null || true
done

# Step 5: Scale down operator to prevent reconciliation during shutdown
print_info "Step 5: Scaling down Rook operator..."
kubectl -n "$CEPH_NAMESPACE" scale deploy/rook-ceph-operator --replicas=0 2>/dev/null || true

print_info "Waiting for all Ceph pods to stop..."
kubectl -n "$CEPH_NAMESPACE" wait --for=delete pod -l app=rook-ceph-mon --timeout=60s 2>/dev/null || true

echo ""
print_success "Ceph gracefully shut down."
print_info "You can now safely run: minikube stop"
print_info "After restart, run: ./components/ceph/scripts/post-start.sh"
