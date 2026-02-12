#!/bin/bash
# Test Ceph Filesystem (CephFS) StorageClass
# Creates a test PVC, pod that uses it, writes data, and cleans up
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

source "$PROJECT_ROOT/scripts/common/utils.sh"

NAMESPACE="default"
PVC_NAME="test-cephfs-pvc"
POD_NAME="test-cephfs-pod"

print_info "Testing Ceph Filesystem (ceph-filesystem StorageClass)"
echo "=========================================="

# Check if StorageClass exists
if ! kubectl get sc ceph-filesystem &>/dev/null; then
    print_error "StorageClass 'ceph-filesystem' not found"
    print_info "Deploy Ceph first: ./components/ceph/scripts/create-cluster.sh"
    exit 1
fi

print_success "StorageClass 'ceph-filesystem' found"

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
    - ReadWriteMany
  storageClassName: ceph-filesystem
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
    command: ["sh", "-c", "echo 'Hello from CephFS!' > /data/test.txt && cat /data/test.txt && sleep 3600"]
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
if [[ "$DATA" == "Hello from CephFS!" ]]; then
    print_success "  Data verified: $DATA"
else
    print_error "Data verification failed. Expected 'Hello from CephFS!', got: $DATA"
    exit 1
fi

# Show PV details
print_info "Step 6: Checking PV details..."
PV_NAME=$(kubectl get pvc $PVC_NAME -n $NAMESPACE -o jsonpath='{.spec.volumeName}')
echo ""
kubectl get pv $PV_NAME

print_success "Ceph Filesystem Test PASSED!"
echo "=========================================="
echo ""
print_info "Test Results:"
echo "  ✓ StorageClass: ceph-filesystem"
echo "  ✓ PVC Created and Bound (ReadWriteMany): $PVC_NAME"
echo "  ✓ PV Provisioned: $PV_NAME"
echo "  ✓ Pod Running: $POD_NAME"
echo "  ✓ Data Written and Read Successfully"
echo ""
print_info "Cleanup:"
echo "  kubectl delete pod $POD_NAME -n $NAMESPACE"
echo "  kubectl delete pvc $PVC_NAME -n $NAMESPACE"
echo ""
print_warning "Note: Run cleanup commands manually or the PVC/PV will remain"
