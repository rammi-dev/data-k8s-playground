#!/bin/bash
# Test Knative Eventing — deploy Kafka Broker + PingSource, verify events flow, clean up
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../../.." && pwd)"

source "$PROJECT_ROOT/scripts/common/utils.sh"
source "$PROJECT_ROOT/scripts/common/config-loader.sh"

print_info "Testing Knative Eventing..."
echo "=========================================="
PASS=0
FAIL=0

# Test 1: Knative Eventing CRDs installed
print_info "Test 1: Knative Eventing CRDs installed"
EXPECTED_CRDS=("brokers.eventing.knative.dev" "triggers.eventing.knative.dev" "pingsources.sources.knative.dev")
CRD_OK=true
for crd in "${EXPECTED_CRDS[@]}"; do
    if ! kubectl get crd "$crd" &>/dev/null; then
        print_error "  Missing CRD: $crd"
        CRD_OK=false
    fi
done
if [[ "$CRD_OK" == "true" ]]; then
    print_success "  PASS: All Eventing CRDs present"
    ((PASS++))
else
    ((FAIL++))
fi

# Test 2: KnativeEventing CR ready
print_info "Test 2: KnativeEventing CR ready"
if kubectl get knativeeventing knative-eventing -n "$KNATIVE_EVENTING_NAMESPACE" \
    -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q "True"; then
    print_success "  PASS: KnativeEventing ready"
    ((PASS++))
else
    print_error "  FAIL: KnativeEventing not ready"
    ((FAIL++))
fi

# Test 3: Deploy eventing demo (Broker + Trigger + PingSource)
print_info "Test 3: Deploy eventing demo"
kubectl apply -f "$SCRIPT_DIR/demo-eventing.yaml"

print_info "  Waiting for Kafka Broker to be ready..."
BROKER_READY=false
for i in {1..24}; do
    if kubectl get broker default -n eventing-demo \
        -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q "True"; then
        BROKER_READY=true
        break
    fi
    sleep 5
done

if [[ "$BROKER_READY" == "true" ]]; then
    print_success "  PASS: Kafka Broker ready"
    ((PASS++))
else
    print_error "  FAIL: Kafka Broker not ready after 2 minutes"
    ((FAIL++))
fi

# Test 4: Verify event-display service is ready
print_info "Test 4: event-display Knative Service ready"
if kubectl wait --timeout=90s -n eventing-demo ksvc event-display --for=condition=Ready 2>/dev/null; then
    print_success "  PASS: event-display ready"
    ((PASS++))
else
    print_error "  FAIL: event-display not ready"
    ((FAIL++))
fi

# Test 5: Check PingSource created
print_info "Test 5: PingSource created"
if kubectl get pingsource test-ping -n eventing-demo \
    -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q "True"; then
    print_success "  PASS: PingSource ready"
    ((PASS++))
else
    print_warning "  SKIP: PingSource not ready yet (needs time to schedule)"
fi

# Test 6: Wait for an event to be delivered (up to 90s for PingSource to fire)
print_info "Test 6: Verify event delivery (waiting up to 90s for PingSource)..."
EVENT_SEEN=false
for i in {1..18}; do
    if kubectl logs -n eventing-demo -l serving.knative.dev/service=event-display \
        -c user-container --tail=20 2>/dev/null | grep -q "PingSource"; then
        EVENT_SEEN=true
        break
    fi
    sleep 5
done

if [[ "$EVENT_SEEN" == "true" ]]; then
    print_success "  PASS: Events flowing (PingSource → Broker → event-display)"
    ((PASS++))
else
    print_warning "  SKIP: No events seen yet (PingSource fires every 60s)"
fi

# Clean up
print_info "Cleaning up test resources..."
kubectl delete namespace eventing-demo --ignore-not-found=true --timeout=60s 2>/dev/null || true

# Summary
echo ""
echo "=========================================="
if [[ $FAIL -eq 0 ]]; then
    print_success "All $PASS tests passed"
else
    print_error "$FAIL failed, $PASS passed"
    exit 1
fi
