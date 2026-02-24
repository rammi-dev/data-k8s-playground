#!/bin/bash
# Test Camel K — verify operator, CRDs, deploy a test integration, tear down
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../../.." && pwd)"

source "$PROJECT_ROOT/scripts/common/utils.sh"
source "$PROJECT_ROOT/scripts/common/config-loader.sh"

NAMESPACE="${CAMEL_K_NAMESPACE:-camel-k}"
TEST_NS="camel-k-test"
PASS=0
FAIL=0
INTEGRATION_CREATED=false

pass() { PASS=$((PASS + 1)); print_success "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); print_error "  FAIL: $1"; }

cleanup() {
    if [[ "$INTEGRATION_CREATED" == "true" ]]; then
        echo ""
        print_info "Cleanup: Removing test integration..."
        kubectl delete integration test-timer -n "$TEST_NS" \
            --ignore-not-found=true --wait=false 2>/dev/null || true
        # Wait for integration pod to be removed
        local i
        for i in $(seq 1 20); do
            if ! kubectl get pods -n "$TEST_NS" -l camel.apache.org/integration=test-timer \
                --no-headers 2>/dev/null | grep -q .; then
                break
            fi
            sleep 3
        done
        kubectl delete namespace "$TEST_NS" --ignore-not-found=true 2>/dev/null || true
        print_success "  Test resources removed"
    fi
}

trap cleanup EXIT

print_info "Testing Camel K..."
echo "=========================================="

# ============================================================================
# PRE-FLIGHT: Verify operator is running
# ============================================================================
print_info "Pre-flight: Verifying Camel K operator is running..."
if ! kubectl get deployment/camel-k-operator -n "$NAMESPACE" \
    -o jsonpath='{.status.availableReplicas}' 2>/dev/null | grep -q "1"; then
    print_error "Camel K operator not running. Deploy first: ./scripts/build.sh"
    exit 1
fi
print_success "  Camel K operator running"

# ============================================================================
# Test 1: Camel K CRDs installed
# ============================================================================
print_info "Test 1: Camel K CRDs installed"
EXPECTED_CRDS=(
    "integrations.camel.apache.org"
    "integrationplatforms.camel.apache.org"
    "integrationkits.camel.apache.org"
    "kamelets.camel.apache.org"
    "pipes.camel.apache.org"
    "builds.camel.apache.org"
    "camelcatalogs.camel.apache.org"
)
CRD_OK=true
for crd in "${EXPECTED_CRDS[@]}"; do
    if ! kubectl get crd "$crd" &>/dev/null; then
        print_error "  Missing CRD: $crd"
        CRD_OK=false
    fi
done
if [[ "$CRD_OK" == "true" ]]; then
    pass "All Camel K CRDs present (${#EXPECTED_CRDS[@]})"
else
    fail "Missing Camel K CRDs"
fi

# ============================================================================
# Test 2: IntegrationPlatform is ready
# ============================================================================
print_info "Test 2: IntegrationPlatform status"
PHASE=$(kubectl get integrationplatform -n "$NAMESPACE" \
    -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "")
if [[ "$PHASE" == "Ready" ]]; then
    pass "IntegrationPlatform ready"
else
    fail "IntegrationPlatform not ready (phase: ${PHASE:-not found})"
fi

# ============================================================================
# Test 3: Deploy a test integration and verify it runs
# ============================================================================
print_info "Test 3: Deploy test integration (timer → log)"

kubectl create namespace "$TEST_NS" --dry-run=client -o yaml | kubectl apply -f -

# Simple integration: timer fires every 2s, logs a message
kubectl apply -n "$TEST_NS" -f - <<'EOF'
apiVersion: camel.apache.org/v1
kind: Integration
metadata:
  name: test-timer
spec:
  flows:
    - from:
        uri: timer:test?period=2000
        steps:
          - setBody:
              constant: "camel-k-test-marker"
          - to: log:test-timer?showBody=true
EOF
INTEGRATION_CREATED=true

# Wait for integration to reach Running phase
print_info "  Waiting for integration to build and run (up to 5 minutes)..."
RUNNING=false
for i in $(seq 1 60); do
    INT_PHASE=$(kubectl get integration test-timer -n "$TEST_NS" \
        -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
    if [[ "$INT_PHASE" == "Running" ]]; then
        RUNNING=true
        break
    fi
    # Show progress every 30s
    if (( i % 6 == 0 )); then
        print_info "  ... waiting (${i}0s elapsed, phase: ${INT_PHASE:-pending})"
    fi
    sleep 5
done

if [[ "$RUNNING" != "true" ]]; then
    fail "Integration did not reach Running phase (phase: ${INT_PHASE:-unknown})"
    kubectl get integration test-timer -n "$TEST_NS" -o yaml 2>/dev/null | tail -20 || true
else
    pass "Integration reached Running phase"
fi

# ============================================================================
# Test 4: Verify integration is producing log output
# ============================================================================
if [[ "$RUNNING" == "true" ]]; then
    print_info "Test 4: Verify integration log output"
    INT_POD=$(kubectl get pods -n "$TEST_NS" -l camel.apache.org/integration=test-timer \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [[ -n "$INT_POD" ]]; then
        # Wait for Camel context to initialize and timer to fire (up to 30s)
        LOG_FOUND=false
        for attempt in $(seq 1 6); do
            sleep 5
            LOGS=$(kubectl logs -n "$TEST_NS" "$INT_POD" --tail=50 2>/dev/null || echo "")
            if echo "$LOGS" | grep -q "camel-k-test-marker"; then
                LOG_FOUND=true
                break
            fi
        done
        if [[ "$LOG_FOUND" == "true" ]]; then
            pass "Integration producing log output"
        else
            fail "Expected 'camel-k-test-marker' in logs, not found"
        fi
    else
        fail "Integration pod not found"
    fi
else
    print_info "Test 4: Skipped (integration not running)"
fi

# ============================================================================
# Summary (cleanup runs via EXIT trap)
# ============================================================================
echo ""
echo "=========================================="
if [[ $FAIL -eq 0 ]]; then
    print_success "All $PASS tests passed"
else
    print_error "$FAIL failed, $PASS passed"
    exit 1
fi
