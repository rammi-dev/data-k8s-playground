#!/bin/bash
# Deploy Knative Serving + Eventing to the Kubernetes cluster using Helm (Knative Operator)
# Requires: Envoy Gateway or Istio deployed (for Gateway API ingress)
# Requires: Strimzi Kafka deployed (for Eventing Kafka Broker)
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
COMPONENT_DIR="$PROJECT_ROOT/components/events/knative"
HELM_DIR="$COMPONENT_DIR/helm"

source "$PROJECT_ROOT/scripts/common/utils.sh"
source "$PROJECT_ROOT/scripts/common/config-loader.sh"

# Check if component is enabled
if [[ "$KNATIVE_ENABLED" != "true" ]]; then
    print_error "Knative is not enabled in config.yaml"
    print_info "Set 'components.knative.enabled: true' in config.yaml"
    exit 1
fi

# Check if Kubernetes cluster is accessible
if ! kubectl cluster-info &>/dev/null; then
    print_error "Kubernetes cluster is not accessible"
    exit 1
fi

print_info "Deploying Knative Serving + Eventing (chart ${KNATIVE_CHART_VERSION})"
print_info "Operator namespace: $KNATIVE_NAMESPACE"
echo "=========================================="

# Determine gateway class
GW_CLASS="eg"
if [[ "$ISTIO_ENABLED" == "true" && "$ENVOY_GATEWAY_ENABLED" != "true" ]]; then
    GW_CLASS="istio"
fi

# ============================================================================
# PRE-FLIGHT: Verify Gateway API controller is available
# ============================================================================
print_info "Verifying Gateway API controller..."
if ! kubectl get gatewayclass "$GW_CLASS" &>/dev/null; then
    print_error "GatewayClass '$GW_CLASS' not found"
    if [[ "$GW_CLASS" == "eg" ]]; then
        print_info "Deploy Envoy Gateway first: ./components/events/envoy-gateway/scripts/build.sh"
    else
        print_info "Deploy Istio first: ./components/events/istio/scripts/build.sh"
    fi
    exit 1
fi
print_success "  GatewayClass '$GW_CLASS' available"

# ============================================================================
# PRE-FLIGHT: Verify Strimzi Kafka is available (for Eventing)
# ============================================================================
print_info "Verifying Kafka cluster..."
if ! kubectl get kafka "$STRIMZI_KAFKA_CLUSTER_NAME" -n "$STRIMZI_NAMESPACE" &>/dev/null; then
    print_error "Kafka cluster '$STRIMZI_KAFKA_CLUSTER_NAME' not found in $STRIMZI_NAMESPACE"
    print_info "Deploy Strimzi first: ./components/events/strimzi/scripts/build.sh"
    exit 1
fi
print_success "  Kafka cluster '$STRIMZI_KAFKA_CLUSTER_NAME' available"

# ============================================================================
# STEP 1: Create namespaces
# ============================================================================
print_info "Step 1: Creating namespaces..."
for ns in "$KNATIVE_NAMESPACE" "$KNATIVE_SERVING_NAMESPACE" "$KNATIVE_EVENTING_NAMESPACE"; do
    kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
done
print_success "  Namespaces ready"

# ============================================================================
# STEP 2: Install Knative Operator via Helm
# ============================================================================
print_info "Step 2: Installing Knative Operator..."

helm repo add knative-operator "$KNATIVE_CHART_REPO" 2>/dev/null || true
helm repo update

print_info "  Updating chart dependencies..."
helm dependency update "$HELM_DIR"

HELM_CMD="helm upgrade --install knative-operator $HELM_DIR \
    -n $KNATIVE_NAMESPACE \
    -f $HELM_DIR/values.yaml \
    -f $HELM_DIR/values-overrides.yaml \
    --wait --timeout=300s"

eval $HELM_CMD

print_info "  Waiting for Knative Operator..."
kubectl wait --timeout=120s -n "$KNATIVE_NAMESPACE" \
    deployment -l app.kubernetes.io/name=knative-operator --for=condition=Available

print_success "  Knative Operator deployed"

# ============================================================================
# STEP 3: Deploy Knative Serving (via KnativeServing CR)
# ============================================================================
print_info "Step 3: Deploying Knative Serving..."

kubectl apply -f "$COMPONENT_DIR/manifests/knative-serving.yaml"

print_info "  Waiting for Knative Serving to be ready (this takes 1-2 minutes)..."
for i in {1..36}; do
    if kubectl get knativeserving knative-serving -n "$KNATIVE_SERVING_NAMESPACE" \
        -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q "True"; then
        break
    fi
    [[ "$i" -eq 36 ]] && { print_error "Knative Serving not ready after 3 minutes"; exit 1; }
    sleep 5
done

print_success "  Knative Serving deployed"

# ============================================================================
# STEP 4: Deploy Knative Eventing + Kafka (via KnativeEventing CR)
# ============================================================================
print_info "Step 4: Deploying Knative Eventing..."

kubectl apply -f "$COMPONENT_DIR/manifests/knative-eventing.yaml"
kubectl apply -f "$COMPONENT_DIR/manifests/kafka-broker-config.yaml"

print_info "  Waiting for Knative Eventing to be ready (this takes 1-2 minutes)..."
for i in {1..36}; do
    if kubectl get knativeeventing knative-eventing -n "$KNATIVE_EVENTING_NAMESPACE" \
        -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q "True"; then
        break
    fi
    [[ "$i" -eq 36 ]] && { print_error "Knative Eventing not ready after 3 minutes"; exit 1; }
    sleep 5
done

print_success "  Knative Eventing deployed"

# ============================================================================
# STATUS
# ============================================================================
print_success "Knative Serving + Eventing Deployed!"
echo "=========================================="
echo ""
print_info "Serving Pods:"
kubectl -n "$KNATIVE_SERVING_NAMESPACE" get pods
echo ""
print_info "Eventing Pods:"
kubectl -n "$KNATIVE_EVENTING_NAMESPACE" get pods
echo ""
print_info "Next steps:"
print_info "  1. Test serving:   ./scripts/test/test-serving.sh"
print_info "  2. Test eventing:  ./scripts/test/test-eventing.sh"
print_info "  3. Check services: kubectl get ksvc -A"
print_info "  4. Check brokers:  kubectl get broker -A"
