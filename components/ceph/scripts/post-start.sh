#!/bin/bash
# Recover Ceph after minikube start
# Handles two scenarios:
#   1. Clean restart (pre-stop.sh was run) - just scales services back up
#   2. Dirty restart (pre-stop.sh was NOT run) - attempts device path repair via operator restart
#
# This script NEVER destroys data. If recovery fails, it tells you to run destroy+build manually.
#
# Run from WSL: ./components/ceph/scripts/post-start.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$PROJECT_ROOT/scripts/common/utils.sh"
source "$PROJECT_ROOT/scripts/common/config-loader.sh"

if ! kubectl cluster-info &>/dev/null; then
    print_error "Kubernetes cluster is not accessible"
    print_info "Make sure minikube is running and kubeconfig is configured"
    exit 1
fi

print_info "=== Ceph Post-Start Recovery ==="

# Check if Ceph namespace exists
if ! kubectl get namespace "$CEPH_NAMESPACE" &>/dev/null; then
    print_error "Namespace $CEPH_NAMESPACE not found. Ceph was never deployed or was fully destroyed."
    print_info "Run: ./components/ceph/scripts/build.sh"
    exit 1
fi

# Step 1: Wait for all nodes to be Ready
print_info "Step 1: Waiting for all nodes to be Ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=300s

# Step 2: Scale up operator first
print_info "Step 2: Starting Rook operator..."
OPERATOR_REPLICAS=$(kubectl -n "$CEPH_NAMESPACE" get deploy rook-ceph-operator -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
if [[ "$OPERATOR_REPLICAS" == "0" ]]; then
    kubectl -n "$CEPH_NAMESPACE" scale deploy/rook-ceph-operator --replicas=1
fi
kubectl -n "$CEPH_NAMESPACE" wait --for=condition=Ready pod -l app=rook-ceph-operator --timeout=120s

# Step 3: Scale up MON
print_info "Step 3: Starting MON..."
for deploy in $(kubectl -n "$CEPH_NAMESPACE" get deploy -l app=rook-ceph-mon -o name 2>/dev/null); do
    REPLICAS=$(kubectl -n "$CEPH_NAMESPACE" get "$deploy" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1")
    if [[ "$REPLICAS" == "0" ]]; then
        kubectl -n "$CEPH_NAMESPACE" scale "$deploy" --replicas=1
    fi
done
sleep 5
kubectl -n "$CEPH_NAMESPACE" wait --for=condition=Ready pod -l app=rook-ceph-mon --timeout=120s 2>/dev/null || true

# Step 4: Scale up MGR
print_info "Step 4: Starting MGR..."
for deploy in $(kubectl -n "$CEPH_NAMESPACE" get deploy -l app=rook-ceph-mgr -o name 2>/dev/null); do
    REPLICAS=$(kubectl -n "$CEPH_NAMESPACE" get "$deploy" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1")
    if [[ "$REPLICAS" == "0" ]]; then
        kubectl -n "$CEPH_NAMESPACE" scale "$deploy" --replicas=1
    fi
done
sleep 5
kubectl -n "$CEPH_NAMESPACE" wait --for=condition=Ready pod -l app=rook-ceph-mgr --timeout=120s 2>/dev/null || true

# Step 5: Check if OSDs need device path repair
print_info "Step 5: Checking OSD device paths..."

NEEDS_REPAIR=false
for deploy in $(kubectl -n "$CEPH_NAMESPACE" get deploy -l app=rook-ceph-osd -o name 2>/dev/null); do
    OSD_ID=$(kubectl -n "$CEPH_NAMESPACE" get "$deploy" -o jsonpath='{.metadata.labels.ceph-osd-id}' 2>/dev/null)
    STORED_PATH=$(kubectl -n "$CEPH_NAMESPACE" get "$deploy" -o jsonpath='{.spec.template.spec.initContainers[0].env[?(@.name=="ROOK_BLOCK_PATH")].value}' 2>/dev/null)
    NODE=$(kubectl -n "$CEPH_NAMESPACE" get "$deploy" -o jsonpath='{.spec.template.spec.nodeSelector.kubernetes\.io/hostname}' 2>/dev/null)

    if [[ -z "$STORED_PATH" ]] || [[ -z "$NODE" ]]; then
        continue
    fi

    print_info "  OSD-$OSD_ID on $NODE: configured device=$STORED_PATH"
done

# Step 6: Scale up OSDs (let operator handle it)
print_info "Step 6: Starting OSDs..."
for deploy in $(kubectl -n "$CEPH_NAMESPACE" get deploy -l app=rook-ceph-osd -o name 2>/dev/null); do
    REPLICAS=$(kubectl -n "$CEPH_NAMESPACE" get "$deploy" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1")
    if [[ "$REPLICAS" == "0" ]]; then
        kubectl -n "$CEPH_NAMESPACE" scale "$deploy" --replicas=1
    fi
done

# Step 7: Wait for OSDs to start, detect failures
print_info "Step 7: Waiting for OSDs to start (up to 90s)..."
OSD_OK=true
for i in {1..18}; do
    sleep 5
    TOTAL=$(kubectl -n "$CEPH_NAMESPACE" get deploy -l app=rook-ceph-osd --no-headers 2>/dev/null | wc -l)
    READY=$(kubectl -n "$CEPH_NAMESPACE" get deploy -l app=rook-ceph-osd --no-headers 2>/dev/null | awk '$2 == "1/1"' | wc -l)
    FAILING=$(kubectl -n "$CEPH_NAMESPACE" get pods -l app=rook-ceph-osd --no-headers 2>/dev/null | grep -cE "Error|CrashLoop|Init:Error" || true)

    if [[ "$READY" -eq "$TOTAL" ]] && [[ "$TOTAL" -gt 0 ]]; then
        print_success "  All $TOTAL OSDs are running"
        break
    fi

    if [[ "$FAILING" -gt 0 ]] && [[ "$i" -ge 12 ]]; then
        print_warning "  $FAILING OSD(s) failing after 60s - attempting device path repair..."
        OSD_OK=false
        break
    fi

    print_info "  OSDs: $READY/$TOTAL ready ($i/18)"
done

# Step 8: If OSDs failed, attempt device path repair
if [[ "$OSD_OK" == "false" ]]; then
    print_info "Step 8: Repairing OSD device paths..."

    # Delete stale OSD deployments - operator will recreate with correct paths
    print_info "  Deleting stale OSD deployments..."
    kubectl -n "$CEPH_NAMESPACE" delete deploy -l app=rook-ceph-osd --wait=false 2>/dev/null || true

    # Delete old OSD prepare jobs
    kubectl -n "$CEPH_NAMESPACE" delete job -l app=rook-ceph-osd-prepare --wait=false 2>/dev/null || true

    # Restart operator to trigger fresh reconciliation
    print_info "  Restarting operator for fresh OSD discovery..."
    kubectl -n "$CEPH_NAMESPACE" rollout restart deploy/rook-ceph-operator
    kubectl -n "$CEPH_NAMESPACE" rollout status deploy/rook-ceph-operator --timeout=60s

    # Wait for operator to run new prepare jobs and create deployments
    print_info "  Waiting for operator to rediscover OSDs (up to 120s)..."
    for i in {1..24}; do
        sleep 5
        TOTAL=$(kubectl -n "$CEPH_NAMESPACE" get deploy -l app=rook-ceph-osd --no-headers 2>/dev/null | wc -l)
        READY=$(kubectl -n "$CEPH_NAMESPACE" get deploy -l app=rook-ceph-osd --no-headers 2>/dev/null | awk '$2 == "1/1"' | wc -l)
        FAILING=$(kubectl -n "$CEPH_NAMESPACE" get pods -l app=rook-ceph-osd --no-headers 2>/dev/null | grep -cE "Error|CrashLoop|Init:Error" || true)

        if [[ "$READY" -eq "$TOTAL" ]] && [[ "$TOTAL" -gt 0 ]]; then
            print_success "  All $TOTAL OSDs recovered"
            OSD_OK=true
            break
        fi

        print_info "  OSDs: $READY/$TOTAL ready ($i/24)"
    done
fi

# Step 9: Scale up remaining services
print_info "Step 9: Starting remaining services..."

# Scale up MDS
for deploy in $(kubectl -n "$CEPH_NAMESPACE" get deploy -l app=rook-ceph-mds -o name 2>/dev/null); do
    REPLICAS=$(kubectl -n "$CEPH_NAMESPACE" get "$deploy" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1")
    if [[ "$REPLICAS" == "0" ]]; then
        kubectl -n "$CEPH_NAMESPACE" scale "$deploy" --replicas=1
    fi
done

# Scale up exporters
for deploy in $(kubectl -n "$CEPH_NAMESPACE" get deploy -l app=rook-ceph-exporter -o name 2>/dev/null); do
    REPLICAS=$(kubectl -n "$CEPH_NAMESPACE" get "$deploy" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1")
    if [[ "$REPLICAS" == "0" ]]; then
        kubectl -n "$CEPH_NAMESPACE" scale "$deploy" --replicas=1
    fi
done

# Scale up RGW
for deploy in $(kubectl -n "$CEPH_NAMESPACE" get deploy -l app=rook-ceph-rgw -o name 2>/dev/null); do
    REPLICAS=$(kubectl -n "$CEPH_NAMESPACE" get "$deploy" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1")
    if [[ "$REPLICAS" == "0" ]]; then
        kubectl -n "$CEPH_NAMESPACE" scale "$deploy" --replicas=1
    fi
done

# Step 10: Unset noout flag
print_info "Step 10: Unsetting OSD noout flag..."
sleep 10
kubectl -n "$CEPH_NAMESPACE" exec deploy/rook-ceph-tools -- ceph osd unset noout 2>/dev/null || true

# Step 11: Final status check
print_info "Step 11: Checking cluster health..."
sleep 10
echo ""
kubectl -n "$CEPH_NAMESPACE" exec deploy/rook-ceph-tools -- ceph status 2>/dev/null || print_warning "Could not get cluster status yet"
echo ""
kubectl -n "$CEPH_NAMESPACE" get pods 2>/dev/null

if [[ "$OSD_OK" == "true" ]]; then
    echo ""
    print_success "Ceph recovery complete!"
else
    echo ""
    print_warning "Some OSDs may still be recovering. Check with:"
    print_info "  kubectl -n $CEPH_NAMESPACE exec deploy/rook-ceph-tools -- ceph status"
    print_info "  kubectl -n $CEPH_NAMESPACE get pods"
    print_info ""
    print_info "If OSDs are still failing, you may need to redeploy:"
    print_info "  ./components/ceph/scripts/destroy.sh && ./components/ceph/scripts/build.sh"
fi
