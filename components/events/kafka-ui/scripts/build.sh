#!/bin/bash
# Deploy Kafbat UI for Kafka topic/consumer group browsing
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
COMPONENT_DIR="$PROJECT_ROOT/components/events/kafka-ui"
HELM_DIR="$COMPONENT_DIR/helm"

source "$PROJECT_ROOT/scripts/common/utils.sh"
source "$PROJECT_ROOT/scripts/common/config-loader.sh"

NAMESPACE="${KAFKA_UI_NAMESPACE:-kafka}"
CHART_VERSION="${KAFKA_UI_CHART_VERSION:-1.6.0}"

print_info "Deploying Kafbat UI (chart v${CHART_VERSION})"
print_info "Namespace: $NAMESPACE"
echo "=========================================="

# ============================================================================
# STEP 1: Install Kafbat UI via Helm
# ============================================================================
print_info "Step 1: Installing Kafbat UI..."

helm repo add kafbat-ui https://kafbat.github.io/helm-charts 2>/dev/null || true
helm repo update kafbat-ui

print_info "  Updating chart dependencies..."
helm dependency update "$HELM_DIR"

helm upgrade --install kafka-ui "$HELM_DIR" \
    -n "$NAMESPACE" \
    -f "$HELM_DIR/values.yaml" \
    -f "$HELM_DIR/values-overrides.yaml" \
    --wait --timeout=120s

print_success "  Kafbat UI deployed"

# ============================================================================
# STEP 2: Wait for pod ready
# ============================================================================
print_info "Step 2: Waiting for Kafbat UI pod..."
kubectl wait --timeout=60s -n "$NAMESPACE" \
    deployment -l app.kubernetes.io/name=kafka-ui --for=condition=Available

print_success "  Kafbat UI ready"

# ============================================================================
# STATUS
# ============================================================================
print_success "Kafbat UI Deployed!"
echo "=========================================="
echo ""
print_info "Pod:"
kubectl -n "$NAMESPACE" get pods -l app.kubernetes.io/name=kafka-ui
echo ""
print_info "Access:"
print_info "  kubectl -n $NAMESPACE port-forward svc/kafka-ui 8080:80"
print_info "  Open http://localhost:8080"
