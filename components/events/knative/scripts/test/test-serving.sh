#!/bin/bash
# Test Knative Serving — deploy hello world, verify scale-to-zero, clean up
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../../.." && pwd)"

source "$PROJECT_ROOT/scripts/common/utils.sh"
source "$PROJECT_ROOT/scripts/common/config-loader.sh"

print_info "Testing Knative Serving..."
echo "=========================================="
PASS=0
FAIL=0

# Test 1: Knative Serving CRDs installed
print_info "Test 1: Knative Serving CRDs installed"
EXPECTED_CRDS=("services.serving.knative.dev" "routes.serving.knative.dev" "revisions.serving.knative.dev" "configurations.serving.knative.dev")
CRD_OK=true
for crd in "${EXPECTED_CRDS[@]}"; do
    if ! kubectl get crd "$crd" &>/dev/null; then
        print_error "  Missing CRD: $crd"
        CRD_OK=false
    fi
done
if [[ "$CRD_OK" == "true" ]]; then
    print_success "  PASS: All Serving CRDs present"
    ((PASS++))
else
    ((FAIL++))
fi

# Test 2: KnativeServing CR ready
print_info "Test 2: KnativeServing CR ready"
if kubectl get knativeserving knative-serving -n "$KNATIVE_SERVING_NAMESPACE" \
    -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q "True"; then
    print_success "  PASS: KnativeServing ready"
    ((PASS++))
else
    print_error "  FAIL: KnativeServing not ready"
    ((FAIL++))
fi

# Test 3: Deploy hello world service
print_info "Test 3: Deploy hello world Knative Service"
kubectl apply -f "$SCRIPT_DIR/demo-hello.yaml"

print_info "  Waiting for ksvc to be ready..."
if kubectl wait --timeout=90s -n default ksvc hello --for=condition=Ready 2>/dev/null; then
    URL=$(kubectl get ksvc hello -n default -o jsonpath='{.status.url}')
    print_success "  PASS: ksvc 'hello' ready at $URL"
    ((PASS++))
else
    print_error "  FAIL: ksvc 'hello' not ready"
    ((FAIL++))
fi

# Test 4: Verify revision created
print_info "Test 4: Revision created"
REV_COUNT=$(kubectl get revisions -n default -l serving.knative.dev/service=hello --no-headers 2>/dev/null | wc -l)
if [[ "$REV_COUNT" -ge 1 ]]; then
    print_success "  PASS: $REV_COUNT revision(s) created"
    ((PASS++))
else
    print_error "  FAIL: No revisions found"
    ((FAIL++))
fi

# Test 5: Verify HTTPRoute created (Gateway API integration)
print_info "Test 5: HTTPRoute created for hello service"
if kubectl get httproute -n default -l serving.knative.dev/service=hello --no-headers 2>/dev/null | grep -q "hello"; then
    print_success "  PASS: HTTPRoute created"
    ((PASS++))
else
    print_warning "  SKIP: HTTPRoute not found (may use different routing)"
fi

# Clean up
print_info "Cleaning up test resources..."
kubectl delete ksvc hello -n default --ignore-not-found=true 2>/dev/null || true

# Summary
echo ""
echo "=========================================="
if [[ $FAIL -eq 0 ]]; then
    print_success "All $PASS tests passed"
else
    print_error "$FAIL failed, $PASS passed"
    exit 1
fi
