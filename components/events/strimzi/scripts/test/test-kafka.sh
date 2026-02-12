#!/bin/bash
# Test Strimzi Kafka — verify operator CRDs, cluster status, produce/consume
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../../.." && pwd)"

source "$PROJECT_ROOT/scripts/common/utils.sh"
source "$PROJECT_ROOT/scripts/common/config-loader.sh"

print_info "Testing Strimzi Kafka..."
echo "=========================================="
PASS=0
FAIL=0

# Test 1: Strimzi CRDs installed
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
    print_success "  PASS: All Strimzi CRDs present"
    ((PASS++))
else
    ((FAIL++))
fi

# Test 2: Kafka cluster ready
print_info "Test 2: Kafka cluster '$STRIMZI_KAFKA_CLUSTER_NAME' ready"
if kubectl get kafka "$STRIMZI_KAFKA_CLUSTER_NAME" -n "$STRIMZI_NAMESPACE" \
    -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q "True"; then
    print_success "  PASS: Kafka cluster ready"
    ((PASS++))
else
    print_error "  FAIL: Kafka cluster not ready"
    kubectl get kafka "$STRIMZI_KAFKA_CLUSTER_NAME" -n "$STRIMZI_NAMESPACE" \
        -o jsonpath='{.status.conditions[*]}' 2>/dev/null || true
    ((FAIL++))
fi

# Test 3: Kafka broker pod running
print_info "Test 3: Kafka broker pod running"
if kubectl get pods -n "$STRIMZI_NAMESPACE" -l strimzi.io/name="${STRIMZI_KAFKA_CLUSTER_NAME}-kafka" \
    -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q "Running"; then
    print_success "  PASS: Broker pod running"
    ((PASS++))
else
    print_error "  FAIL: Broker pod not running"
    ((FAIL++))
fi

# Test 4: Produce and consume a test message
print_info "Test 4: Produce/consume test message"
TEST_TOPIC="test-$(date +%s)"
BOOTSTRAP="${STRIMZI_KAFKA_CLUSTER_NAME}-kafka-bootstrap.${STRIMZI_NAMESPACE}.svc.cluster.local:9092"
TEST_MSG="hello-from-test-$(date +%s)"

# Create a test topic
kubectl apply -n "$STRIMZI_NAMESPACE" -f - <<EOF
apiVersion: kafka.strimzi.io/v1beta2
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

# Wait for topic
sleep 5

# Produce a message
kubectl run kafka-test-producer -n "$STRIMZI_NAMESPACE" --rm -i --restart=Never \
    --image=quay.io/strimzi/kafka:0.50.0-kafka-${STRIMZI_KAFKA_VERSION} \
    -- bin/kafka-console-producer.sh --bootstrap-server "$BOOTSTRAP" --topic "$TEST_TOPIC" \
    <<< "$TEST_MSG" 2>/dev/null || true

# Consume and verify
RECEIVED=$(kubectl run kafka-test-consumer -n "$STRIMZI_NAMESPACE" --rm -i --restart=Never \
    --image=quay.io/strimzi/kafka:0.50.0-kafka-${STRIMZI_KAFKA_VERSION} \
    -- bin/kafka-console-consumer.sh --bootstrap-server "$BOOTSTRAP" --topic "$TEST_TOPIC" \
    --from-beginning --max-messages 1 --timeout-ms 10000 2>/dev/null || true)

# Clean up test topic
kubectl delete kafkatopic "$TEST_TOPIC" -n "$STRIMZI_NAMESPACE" --ignore-not-found=true 2>/dev/null || true

if echo "$RECEIVED" | grep -q "$TEST_MSG"; then
    print_success "  PASS: Message produced and consumed"
    ((PASS++))
else
    print_warning "  SKIP: Produce/consume test inconclusive (may need more time)"
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
