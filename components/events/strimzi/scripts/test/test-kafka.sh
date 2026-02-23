#!/bin/bash
# Test Strimzi Kafka — create cluster, verify, produce/consume, tear down
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../../.." && pwd)"
MANIFESTS_DIR="$SCRIPT_DIR/manifests"

source "$PROJECT_ROOT/scripts/common/utils.sh"
source "$PROJECT_ROOT/scripts/common/config-loader.sh"

PASS=0
FAIL=0
CLUSTER_CREATED=false

pass() { PASS=$((PASS + 1)); print_success "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); print_error "  FAIL: $1"; }

cleanup() {
    if [[ "$CLUSTER_CREATED" == "true" ]]; then
        echo ""
        print_info "Cleanup: Removing test Kafka cluster..."
        kubectl delete -f "$MANIFESTS_DIR/" -n "$STRIMZI_NAMESPACE" \
            --ignore-not-found=true --wait=false 2>/dev/null || true
        # Wait for Kafka CR to be deleted (operator handles pod cleanup)
        local i
        for i in $(seq 1 30); do
            if ! kubectl get kafka "$STRIMZI_KAFKA_CLUSTER_NAME" -n "$STRIMZI_NAMESPACE" &>/dev/null; then
                print_success "  Test cluster removed"
                return
            fi
            sleep 5
        done
        print_warning "  Cluster deletion still in progress (may take a minute)"
    fi
}

trap cleanup EXIT

print_info "Testing Strimzi Kafka..."
echo "=========================================="

# ============================================================================
# PRE-FLIGHT: Verify operator is running
# ============================================================================
print_info "Pre-flight: Verifying Strimzi operator is running..."
if ! kubectl get deployment/strimzi-cluster-operator -n "$STRIMZI_NAMESPACE" \
    -o jsonpath='{.status.availableReplicas}' 2>/dev/null | grep -q "1"; then
    print_error "Strimzi operator not running. Deploy first: ./scripts/build.sh"
    exit 1
fi
print_success "  Strimzi operator running"

# ============================================================================
# Test 1: Strimzi CRDs installed
# ============================================================================
print_info "Test 1: Strimzi CRDs installed"
EXPECTED_CRDS=("kafkas.kafka.strimzi.io" "kafkanodepools.kafka.strimzi.io" "kafkatopics.kafka.strimzi.io")
CRD_OK=true
for crd in "${EXPECTED_CRDS[@]}"; do
    if ! kubectl get crd "$crd" &>/dev/null; then
        print_error "  Missing CRD: $crd"
        CRD_OK=false
    fi
done
if [[ "$CRD_OK" == "true" ]]; then
    pass "All Strimzi CRDs present"
else
    fail "Missing Strimzi CRDs"
fi

# ============================================================================
# CREATE: Deploy test Kafka cluster (1 dual-role node, KRaft)
# ============================================================================
print_info "Creating test Kafka cluster (${STRIMZI_KAFKA_CLUSTER_NAME})..."
kubectl apply -f "$MANIFESTS_DIR/" -n "$STRIMZI_NAMESPACE"
CLUSTER_CREATED=true

# Wait for Kafka ready (takes 2-3 minutes)
print_info "  Waiting for Kafka cluster to be ready (up to 5 minutes)..."
READY=false
for i in $(seq 1 60); do
    STATUS=$(kubectl get kafka "$STRIMZI_KAFKA_CLUSTER_NAME" -n "$STRIMZI_NAMESPACE" \
        -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
    if [[ "$STATUS" == "True" ]]; then
        READY=true
        break
    fi
    # Show progress every 30s
    if (( i % 6 == 0 )); then
        PHASE=$(kubectl get pods -n "$STRIMZI_NAMESPACE" \
            -l strimzi.io/cluster="${STRIMZI_KAFKA_CLUSTER_NAME}" \
            --no-headers 2>/dev/null | head -1 | awk '{print $3}' || true)
        print_info "  ... waiting (${i}0s elapsed, pod status: ${PHASE:-pending})"
    fi
    sleep 5
done

if [[ "$READY" != "true" ]]; then
    print_error "Kafka cluster not ready after 5 minutes"
    kubectl get pods -n "$STRIMZI_NAMESPACE" 2>/dev/null || true
    kubectl get kafka "$STRIMZI_KAFKA_CLUSTER_NAME" -n "$STRIMZI_NAMESPACE" -o yaml 2>/dev/null | tail -20 || true
    exit 1
fi
print_success "  Kafka cluster ready"

# ============================================================================
# Test 2: Kafka broker pod running
# ============================================================================
print_info "Test 2: Kafka broker pod running"
BROKER_PHASE=$(kubectl get pods -n "$STRIMZI_NAMESPACE" \
    -l strimzi.io/name="${STRIMZI_KAFKA_CLUSTER_NAME}-kafka" \
    -o jsonpath='{.items[0].status.phase}' 2>/dev/null || true)
if [[ "$BROKER_PHASE" == "Running" ]]; then
    pass "Broker pod running"
else
    fail "Broker pod not running (phase: ${BROKER_PHASE:-not found})"
fi

# ============================================================================
# Test 3: Entity Operator running
# ============================================================================
print_info "Test 3: Entity Operator running"
EO_PHASE=$(kubectl get pods -n "$STRIMZI_NAMESPACE" \
    -l strimzi.io/name="${STRIMZI_KAFKA_CLUSTER_NAME}-entity-operator" \
    -o jsonpath='{.items[0].status.phase}' 2>/dev/null || true)
if [[ "$EO_PHASE" == "Running" ]]; then
    pass "Entity Operator running"
else
    fail "Entity Operator not running (phase: ${EO_PHASE:-not found})"
fi

# ============================================================================
# Test 4: Produce and consume a test message
# ============================================================================
print_info "Test 4: Produce/consume round-trip"
TEST_TOPIC="test-roundtrip-$(date +%s)"
TEST_MSG="hello-$(date +%s)"

# Create a test topic via CRD
kubectl apply -n "$STRIMZI_NAMESPACE" -f - <<EOF
apiVersion: kafka.strimzi.io/v1
kind: KafkaTopic
metadata:
  name: $TEST_TOPIC
  labels:
    strimzi.io/cluster: $STRIMZI_KAFKA_CLUSTER_NAME
spec:
  partitions: 1
  replicas: 1
  config:
    retention.ms: "60000"
EOF

# Wait for topic to be created
print_info "  Waiting for topic..."
for i in $(seq 1 12); do
    TOPIC_READY=$(kubectl get kafkatopic "$TEST_TOPIC" -n "$STRIMZI_NAMESPACE" \
        -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
    if [[ "$TOPIC_READY" == "True" ]]; then break; fi
    sleep 5
done

# Produce a message using exec into the broker pod (avoids pulling extra images)
BROKER_POD=$(kubectl get pods -n "$STRIMZI_NAMESPACE" \
    -l strimzi.io/name="${STRIMZI_KAFKA_CLUSTER_NAME}-kafka" \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

print_info "  Producing message..."
kubectl exec -n "$STRIMZI_NAMESPACE" "$BROKER_POD" -- bash -c \
    "echo '$TEST_MSG' | bin/kafka-console-producer.sh --bootstrap-server localhost:9092 --topic $TEST_TOPIC" \
    2>/dev/null || true

# Consume and verify
print_info "  Consuming message..."
RECEIVED=$(kubectl exec -n "$STRIMZI_NAMESPACE" "$BROKER_POD" -- \
    bin/kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic "$TEST_TOPIC" \
    --from-beginning --max-messages 1 --timeout-ms 15000 2>/dev/null || true)

# Clean up test topic
kubectl delete kafkatopic "$TEST_TOPIC" -n "$STRIMZI_NAMESPACE" \
    --ignore-not-found=true 2>/dev/null || true

if echo "$RECEIVED" | grep -q "$TEST_MSG"; then
    pass "Message produced and consumed successfully"
else
    fail "Produce/consume round-trip failed (expected: $TEST_MSG, got: ${RECEIVED:-empty})"
fi

# ============================================================================
# Summary (cleanup runs via EXIT trap)
# ============================================================================
echo ""
echo "=========================================="
print_info "Pods at end of test:"
kubectl get pods -n "$STRIMZI_NAMESPACE" --no-headers 2>/dev/null || true
echo "=========================================="
if [[ $FAIL -eq 0 ]]; then
    print_success "All $PASS tests passed"
else
    print_error "$FAIL failed, $PASS passed"
    exit 1
fi
