#!/bin/bash
# Test Istio Service Mesh — verify istiod, mTLS, sidecar injection, policies
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../../.." && pwd)"

source "$PROJECT_ROOT/scripts/common/utils.sh"
source "$PROJECT_ROOT/scripts/common/config-loader.sh"

print_info "Testing Istio Service Mesh..."
echo "=========================================="
PASS=0
FAIL=0

# Test 1: Istio CRDs installed
print_info "Test 1: Istio CRDs installed"
EXPECTED_CRDS=("peerauthentications.security.istio.io" "authorizationpolicies.security.istio.io" "virtualservices.networking.istio.io")
CRD_OK=true
for crd in "${EXPECTED_CRDS[@]}"; do
    if ! kubectl get crd "$crd" &>/dev/null; then
        print_error "  Missing CRD: $crd"
        CRD_OK=false
    fi
done
if [[ "$CRD_OK" == "true" ]]; then
    print_success "  PASS: All Istio CRDs present"
    ((PASS++))
else
    ((FAIL++))
fi

# Test 2: istiod running
print_info "Test 2: istiod control plane running"
if kubectl get pods -n "$ISTIO_NAMESPACE" -l app=istiod \
    -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q "Running"; then
    print_success "  PASS: istiod running"
    ((PASS++))
else
    print_error "  FAIL: istiod not running"
    ((FAIL++))
fi

# Test 3: GatewayClass 'istio' exists
print_info "Test 3: GatewayClass 'istio' exists"
if kubectl get gatewayclass istio &>/dev/null; then
    print_success "  PASS: GatewayClass 'istio' exists"
    ((PASS++))
else
    print_error "  FAIL: GatewayClass 'istio' not found"
    ((FAIL++))
fi

# Test 4: PeerAuthentication STRICT
print_info "Test 4: mTLS STRICT mode active"
MTLS_MODE=$(kubectl get peerauthentication -n "$ISTIO_NAMESPACE" -o jsonpath='{.items[0].spec.mtls.mode}' 2>/dev/null)
if [[ "$MTLS_MODE" == "STRICT" ]]; then
    print_success "  PASS: mTLS STRICT active"
    ((PASS++))
else
    print_error "  FAIL: mTLS mode is '$MTLS_MODE' (expected STRICT)"
    ((FAIL++))
fi

# Test 5: Sidecar injection labels
print_info "Test 5: Sidecar injection labels on workload namespaces"
INJECT_OK=true
for ns in default; do
    LABEL=$(kubectl get namespace "$ns" -o jsonpath='{.metadata.labels.istio-injection}' 2>/dev/null)
    if [[ "$LABEL" != "enabled" ]]; then
        print_error "  Namespace '$ns' missing istio-injection=enabled"
        INJECT_OK=false
    fi
done
if [[ "$INJECT_OK" == "true" ]]; then
    print_success "  PASS: Sidecar injection labels set"
    ((PASS++))
else
    ((FAIL++))
fi

# Test 6: Verify sidecar proxy in a workload pod
print_info "Test 6: Sidecar proxy present in workload pods"
SIDECAR_FOUND=false
for pod in $(kubectl get pods -n default -o name 2>/dev/null | head -3); do
    CONTAINERS=$(kubectl get "$pod" -n default -o jsonpath='{.spec.containers[*].name}' 2>/dev/null)
    if echo "$CONTAINERS" | grep -q "istio-proxy"; then
        SIDECAR_FOUND=true
        break
    fi
done
if [[ "$SIDECAR_FOUND" == "true" ]]; then
    print_success "  PASS: istio-proxy sidecar found"
    ((PASS++))
else
    print_warning "  SKIP: No workload pods with sidecar found in default namespace"
fi

# Test 7: AuthorizationPolicy exists
print_info "Test 7: AuthorizationPolicy applied"
AP_COUNT=$(kubectl get authorizationpolicy -A --no-headers 2>/dev/null | wc -l)
if [[ "$AP_COUNT" -ge 1 ]]; then
    print_success "  PASS: $AP_COUNT AuthorizationPolicy(s) found"
    ((PASS++))
else
    print_error "  FAIL: No AuthorizationPolicy found"
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
