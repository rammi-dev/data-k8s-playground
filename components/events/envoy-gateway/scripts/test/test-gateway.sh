#!/bin/bash
# Test Envoy Gateway — verify GatewayClass + Gateway are functional
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../../.." && pwd)"

source "$PROJECT_ROOT/scripts/common/utils.sh"
source "$PROJECT_ROOT/scripts/common/config-loader.sh"

print_info "Testing Envoy Gateway..."
echo "=========================================="
PASS=0
FAIL=0

# Test 1: GatewayClass exists and accepted
print_info "Test 1: GatewayClass 'eg' exists and accepted"
if kubectl get gatewayclass eg -o jsonpath='{.status.conditions[?(@.type=="Accepted")].status}' 2>/dev/null | grep -q "True"; then
    print_success "  PASS: GatewayClass 'eg' accepted"
    ((PASS++))
else
    print_error "  FAIL: GatewayClass 'eg' not accepted"
    ((FAIL++))
fi

# Test 2: Gateway programmed
print_info "Test 2: Gateway 'knative-gateway' programmed"
if kubectl get gateway knative-gateway -n "$KNATIVE_SERVING_NAMESPACE" \
    -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}' 2>/dev/null | grep -q "True"; then
    print_success "  PASS: Gateway programmed"
    ((PASS++))
else
    print_error "  FAIL: Gateway not programmed"
    ((FAIL++))
fi

# Test 3: Controller pod running
print_info "Test 3: Envoy Gateway controller running"
if kubectl get pods -n "$ENVOY_GATEWAY_NAMESPACE" -l control-plane=envoy-gateway \
    -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q "Running"; then
    print_success "  PASS: Controller running"
    ((PASS++))
else
    print_error "  FAIL: Controller not running"
    ((FAIL++))
fi

# Test 4: Gateway API CRDs installed
print_info "Test 4: Gateway API CRDs installed"
EXPECTED_CRDS=("gateways.gateway.networking.k8s.io" "gatewayclasses.gateway.networking.k8s.io" "httproutes.gateway.networking.k8s.io")
CRD_OK=true
for crd in "${EXPECTED_CRDS[@]}"; do
    if ! kubectl get crd "$crd" &>/dev/null; then
        print_error "  Missing CRD: $crd"
        CRD_OK=false
    fi
done
if [[ "$CRD_OK" == "true" ]]; then
    print_success "  PASS: All Gateway API CRDs present"
    ((PASS++))
else
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
