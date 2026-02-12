#!/bin/bash
# Deploy Envoy Gateway to the Kubernetes cluster using Helm
# Provides Gateway API controller for Knative Serving ingress
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
COMPONENT_DIR="$PROJECT_ROOT/components/events/envoy-gateway"
HELM_DIR="$COMPONENT_DIR/helm"

source "$PROJECT_ROOT/scripts/common/utils.sh"
source "$PROJECT_ROOT/scripts/common/config-loader.sh"

# Check if component is enabled
if [[ "$ENVOY_GATEWAY_ENABLED" != "true" ]]; then
    print_error "Envoy Gateway is not enabled in config.yaml"
    print_info "Set 'components.envoy_gateway.enabled: true' in config.yaml"
    exit 1
fi

# Check if Kubernetes cluster is accessible
if ! kubectl cluster-info &>/dev/null; then
    print_error "Kubernetes cluster is not accessible"
    exit 1
fi

print_info "Deploying Envoy Gateway (chart ${ENVOY_GATEWAY_CHART_VERSION})"
print_info "Namespace: $ENVOY_GATEWAY_NAMESPACE"
echo "=========================================="

# ============================================================================
# STEP 1: Create namespace
# ============================================================================
print_info "Step 1: Creating namespace..."
kubectl create namespace "$ENVOY_GATEWAY_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
print_success "  Namespace $ENVOY_GATEWAY_NAMESPACE ready"

# ============================================================================
# STEP 2: Install Envoy Gateway via Helm
# ============================================================================
print_info "Step 2: Installing Envoy Gateway..."

print_info "  Updating chart dependencies..."
helm dependency update "$HELM_DIR"

HELM_CMD="helm upgrade --install envoy-gateway $HELM_DIR \
    -n $ENVOY_GATEWAY_NAMESPACE \
    -f $HELM_DIR/values.yaml \
    -f $HELM_DIR/values-overrides.yaml \
    --wait --timeout=300s"

eval $HELM_CMD

print_info "  Waiting for Envoy Gateway controller..."
kubectl wait --timeout=120s -n "$ENVOY_GATEWAY_NAMESPACE" \
    deployment/envoy-gateway --for=condition=Available

print_success "  Envoy Gateway deployed"

# ============================================================================
# STEP 3: Apply Gateway resource for Knative
# ============================================================================
print_info "Step 3: Applying Gateway resource..."

# Ensure knative-serving namespace exists (may not yet if Knative not deployed)
kubectl create namespace "$KNATIVE_SERVING_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f "$HELM_DIR/templates/custom/"

print_success "  Gateway resource applied"

# ============================================================================
# STATUS
# ============================================================================
print_success "Envoy Gateway Deployed!"
echo "=========================================="
echo ""
print_info "Installed Components:"
echo "  - Envoy Gateway controller"
echo "  - Gateway API CRDs (GatewayClass, Gateway, HTTPRoute, etc.)"
echo "  - GatewayClass 'eg' (auto-created)"
echo "  - Gateway 'knative-gateway' in $KNATIVE_SERVING_NAMESPACE"
echo ""
print_info "Next steps:"
print_info "  1. Deploy Knative Serving: ./components/events/knative/scripts/build.sh"
print_info "  2. Test Gateway API:       kubectl get gateway -A"
