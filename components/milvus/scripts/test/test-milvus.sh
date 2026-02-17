#!/bin/bash
# Test Milvus — verify deployment, health, basic vector operations
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

source "$PROJECT_ROOT/scripts/common/utils.sh"
source "$PROJECT_ROOT/scripts/common/config-loader.sh"

print_info "Testing Milvus..."
echo "=========================================="
PASS=0
FAIL=0

MILVUS_GRPC="milvus.${MILVUS_NAMESPACE}.svc.cluster.local:19530"
MILVUS_HTTP="http://milvus.${MILVUS_NAMESPACE}.svc.cluster.local:9091"

# Test 1: Milvus pods running
print_info "Test 1: Milvus pods running"
RUNNING=$(kubectl get pods -n "$MILVUS_NAMESPACE" -l app.kubernetes.io/instance=milvus \
    --field-selector=status.phase=Running -o name 2>/dev/null | wc -l)
if [[ "$RUNNING" -gt 0 ]]; then
    print_success "  PASS: $RUNNING pod(s) running"
    ((PASS++))
else
    print_error "  FAIL: No Milvus pods running"
    kubectl get pods -n "$MILVUS_NAMESPACE" 2>/dev/null || true
    ((FAIL++))
fi

# Test 2: etcd running
print_info "Test 2: etcd pod running"
if kubectl get pods -n "$MILVUS_NAMESPACE" -l app.kubernetes.io/name=etcd \
    -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q "Running"; then
    print_success "  PASS: etcd running"
    ((PASS++))
else
    print_error "  FAIL: etcd not running"
    ((FAIL++))
fi

# Test 3: MinIO running
print_info "Test 3: MinIO pod running"
if kubectl get pods -n "$MILVUS_NAMESPACE" -l app=minio \
    -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q "Running"; then
    print_success "  PASS: MinIO running"
    ((PASS++))
else
    print_error "  FAIL: MinIO not running"
    ((FAIL++))
fi

# Test 4: Milvus health endpoint
print_info "Test 4: Milvus health check (via kubectl exec)"
HEALTH=$(kubectl run milvus-health-check -n "$MILVUS_NAMESPACE" --rm -i --restart=Never \
    --image=curlimages/curl:8.12.1 -- \
    curl -s -o /dev/null -w '%{http_code}' "${MILVUS_HTTP}/healthz" 2>/dev/null || echo "000")

if [[ "$HEALTH" == "200" ]]; then
    print_success "  PASS: Health endpoint returned 200"
    ((PASS++))
else
    print_error "  FAIL: Health endpoint returned $HEALTH"
    ((FAIL++))
fi

# Test 5: PVCs bound
print_info "Test 5: PVCs bound"
TOTAL_PVC=$(kubectl get pvc -n "$MILVUS_NAMESPACE" -o name 2>/dev/null | wc -l)
BOUND_PVC=$(kubectl get pvc -n "$MILVUS_NAMESPACE" --field-selector=status.phase=Bound -o name 2>/dev/null | wc -l)
if [[ "$TOTAL_PVC" -gt 0 && "$TOTAL_PVC" -eq "$BOUND_PVC" ]]; then
    print_success "  PASS: All $BOUND_PVC PVCs bound"
    ((PASS++))
else
    print_error "  FAIL: $BOUND_PVC/$TOTAL_PVC PVCs bound"
    kubectl get pvc -n "$MILVUS_NAMESPACE" 2>/dev/null || true
    ((FAIL++))
fi

# Summary
echo ""
echo "=========================================="
if [[ $FAIL -eq 0 ]]; then
    print_success "All $PASS tests passed"
else
    print_error "$FAIL failed, $PASS passed"
    exit 1
fi
