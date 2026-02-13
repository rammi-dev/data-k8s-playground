#!/bin/bash
# Test Ceph Block Storage (RBD) StorageClass
# Creates a test PVC, pod that uses it, writes data, and cleans up
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

source "$PROJECT_ROOT/scripts/common/utils.sh"

NAMESPACE="default"
PVC_NAME="test-rbd-pvc"
POD_NAME="test-rbd-pod"
TEST_PASSED=false

cleanup() {
    echo ""
    print_info "Cleaning up test resources..."
    kubectl delete pod "$POD_NAME" -n "$NAMESPACE" --ignore-not-found --wait=false 2>/dev/null
    kubectl wait --for=delete pod/"$POD_NAME" -n "$NAMESPACE" --timeout=30s 2>/dev/null || true
    kubectl delete pvc "$PVC_NAME" -n "$NAMESPACE" --ignore-not-found --wait=false 2>/dev/null
    kubectl wait --for=delete pvc/"$PVC_NAME" -n "$NAMESPACE" --timeout=30s 2>/dev/null || true
    if $TEST_PASSED; then
        print_success "Cleanup complete"
    else
        print_error "Test FAILED - resources cleaned up"
        exit 1
    fi
}
trap cleanup EXIT

print_info "Testing Ceph Block Storage (ceph-block StorageClass)"
echo "=========================================="

# Check if StorageClass exists
if ! kubectl get sc ceph-block &>/dev/null; then
    print_error "StorageClass 'ceph-block' not found"
    print_info "Deploy Ceph first: ./components/ceph/scripts/build.sh"
    exit 1
fi

print_success "StorageClass 'ceph-block' found"

# Create test PVC
print_info "Step 1: Creating test PVC..."
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: $PVC_NAME
  namespace: $NAMESPACE
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: ceph-block
  resources:
    requests:
      storage: 1Gi
EOF

# Wait for PVC to be bound
print_info "Step 2: Waiting for PVC to bind..."
for i in {1..30}; do
    STATUS=$(kubectl get pvc $PVC_NAME -n $NAMESPACE -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
    if [[ "$STATUS" == "Bound" ]]; then
        print_success "  PVC bound successfully"
        break
    fi
    if [[ "$i" -eq 30 ]]; then
        print_error "PVC did not bind after 30 seconds"
        kubectl describe pvc $PVC_NAME -n $NAMESPACE
        exit 1
    fi
    sleep 1
done

# Create test pod
print_info "Step 3: Creating test pod..."
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: $POD_NAME
  namespace: $NAMESPACE
spec:
  containers:
  - name: test
    image: busybox
    command: ["sh", "-c", "echo 'Hello from Ceph RBD!' > /data/test.txt && cat /data/test.txt && sleep 3600"]
    volumeMounts:
    - name: data
      mountPath: /data
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: $PVC_NAME
EOF

# Wait for pod to be ready
print_info "Step 4: Waiting for pod to be ready..."
kubectl wait --for=condition=Ready pod/$POD_NAME -n $NAMESPACE --timeout=60s

# Verify data was written
print_info "Step 5: Verifying data..."
DATA=$(kubectl exec $POD_NAME -n $NAMESPACE -- cat /data/test.txt 2>/dev/null || echo "")
if [[ "$DATA" == "Hello from Ceph RBD!" ]]; then
    print_success "  Data verified: $DATA"
else
    print_error "Data verification failed. Expected 'Hello from Ceph RBD!', got: $DATA"
    exit 1
fi

# Show PV details
print_info "Step 6: Checking PV details..."
PV_NAME=$(kubectl get pvc $PVC_NAME -n $NAMESPACE -o jsonpath='{.spec.volumeName}')
echo ""
kubectl get pv $PV_NAME

TEST_PASSED=true
print_success "Ceph Block Storage Test PASSED!"
echo "=========================================="
echo ""
print_info "Test Results:"
echo "  ✓ StorageClass: ceph-block"
echo "  ✓ PVC Created and Bound: $PVC_NAME"
echo "  ✓ PV Provisioned: $PV_NAME"
echo "  ✓ Pod Running: $POD_NAME"
echo "  ✓ Data Written and Read Successfully"
