#!/bin/bash
# Test Kafbat UI deployment
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../../.." && pwd)"

source "$PROJECT_ROOT/scripts/common/utils.sh"
source "$PROJECT_ROOT/scripts/common/config-loader.sh"

NAMESPACE="${KAFKA_UI_NAMESPACE:-kafka}"
FAILED=0
PASSED=0

pass() { print_success "  PASS: $1"; ((PASSED++)) || true; }
fail() { print_error "  FAIL: $1"; ((FAILED++)) || true; }

print_info "Testing Kafbat UI..."
echo "=========================================="

# Test 1: Pod running
print_info "Test 1: Kafbat UI pod running"
if kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=kafka-ui --no-headers 2>/dev/null | grep -q "Running"; then
    pass "Kafbat UI pod running"
else
    fail "Kafbat UI pod not running"
fi

# Test 2: Service exists
print_info "Test 2: Service exists"
if kubectl get svc -n "$NAMESPACE" -l app.kubernetes.io/name=kafka-ui --no-headers 2>/dev/null | grep -q .; then
    pass "Service exists"
else
    fail "Service not found"
fi

# Test 3: API responds (port-forward + curl)
print_info "Test 3: API health check"
kubectl -n "$NAMESPACE" port-forward svc/kafka-ui 18080:80 &>/dev/null &
PF_PID=$!
sleep 3

if curl -s -o /dev/null -w "%{http_code}" http://localhost:18080/api/clusters 2>/dev/null | grep -q "200"; then
    pass "API responds (HTTP 200 on /api/clusters)"
else
    fail "API not responding on /api/clusters"
fi

kill $PF_PID 2>/dev/null || true

# Summary
echo ""
echo "=========================================="
if [[ $FAILED -gt 0 ]]; then
    print_error "$FAILED failed, $PASSED passed"
    exit 1
else
    print_success "All $PASSED tests passed"
fi
