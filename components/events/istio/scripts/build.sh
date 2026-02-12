#!/bin/bash
# Deploy Istio service mesh to the Kubernetes cluster using Helm (Phase 3)
# Replaces Envoy Gateway as the Gateway API controller and adds mesh features
# Requires: Knative already deployed (for gateway swap)
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
COMPONENT_DIR="$PROJECT_ROOT/components/events/istio"
HELM_DIR="$COMPONENT_DIR/helm"

source "$PROJECT_ROOT/scripts/common/utils.sh"
source "$PROJECT_ROOT/scripts/common/config-loader.sh"

# Check if component is enabled
if [[ "$ISTIO_ENABLED" != "true" ]]; then
    print_error "Istio is not enabled in config.yaml"
    print_info "Set 'components.istio.enabled: true' in config.yaml"
    exit 1
fi

# Check if Kubernetes cluster is accessible
if ! kubectl cluster-info &>/dev/null; then
    print_error "Kubernetes cluster is not accessible"
    exit 1
fi

print_info "Deploying Istio Service Mesh (chart ${ISTIO_CHART_VERSION})"
print_info "Namespace: $ISTIO_NAMESPACE"
echo "=========================================="

# ============================================================================
# STEP 1: Create namespace
# ============================================================================
print_info "Step 1: Creating namespace..."
kubectl create namespace "$ISTIO_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
print_success "  Namespace $ISTIO_NAMESPACE ready"

# ============================================================================
# STEP 2: Install Istio via Helm (base + istiod)
# ============================================================================
print_info "Step 2: Installing Istio..."

helm repo add istio "$ISTIO_CHART_REPO" 2>/dev/null || true
helm repo update

print_info "  Updating chart dependencies..."
helm dependency update "$HELM_DIR"

HELM_CMD="helm upgrade --install istio $HELM_DIR \
    -n $ISTIO_NAMESPACE \
    -f $HELM_DIR/values.yaml \
    -f $HELM_DIR/values-overrides.yaml \
    --wait --timeout=300s"

eval $HELM_CMD

print_info "  Waiting for istiod..."
kubectl wait --timeout=120s -n "$ISTIO_NAMESPACE" \
    deployment -l app=istiod --for=condition=Available

print_success "  Istio deployed"

# ============================================================================
# STEP 3: Swap Gateway API controller (Envoy Gateway -> Istio)
# ============================================================================
print_info "Step 3: Swapping Gateway API controller to Istio..."

if kubectl get configmap config-gateway -n "$KNATIVE_SERVING_NAMESPACE" &>/dev/null; then
    kubectl patch configmap config-gateway -n "$KNATIVE_SERVING_NAMESPACE" \
        --type merge -p "{\"data\":{
            \"external-gateways\": \"[{\\\"class\\\": \\\"istio\\\", \\\"gateway\\\": \\\"${KNATIVE_SERVING_NAMESPACE}/knative-gateway\\\", \\\"supported-features\\\": [\\\"HTTPRouteRequestTimeout\\\"]}]\",
            \"local-gateways\": \"[{\\\"class\\\": \\\"istio\\\", \\\"gateway\\\": \\\"${KNATIVE_SERVING_NAMESPACE}/knative-gateway\\\", \\\"supported-features\\\": [\\\"HTTPRouteRequestTimeout\\\"]}]\"
        }}"

    kubectl patch gateway knative-gateway -n "$KNATIVE_SERVING_NAMESPACE" \
        --type merge -p '{"spec":{"gatewayClassName":"istio"}}'

    print_success "  Knative gateway switched to Istio"
else
    print_warning "  Knative Serving not found, skipping gateway swap"
fi

# ============================================================================
# STEP 4: Enable sidecar injection
# ============================================================================
print_info "Step 4: Enabling sidecar injection..."

for ns in default eventing-demo; do
    if kubectl get namespace "$ns" &>/dev/null; then
        kubectl label namespace "$ns" istio-injection=enabled --overwrite
        print_success "  Labeled $ns for injection"
    fi
done

# Restart deployments to pick up sidecars
print_info "  Restarting deployments for sidecar injection..."
for ns in default eventing-demo; do
    if kubectl get namespace "$ns" &>/dev/null; then
        kubectl rollout restart deployment -n "$ns" 2>/dev/null || true
    fi
done

# ============================================================================
# STEP 5: Apply mesh policies
# ============================================================================
print_info "Step 5: Applying mesh policies..."

kubectl apply -f "$COMPONENT_DIR/manifests/"

print_success "  mTLS (STRICT) and AuthorizationPolicy applied"

# ============================================================================
# STATUS
# ============================================================================
print_success "Istio Service Mesh Deployed!"
echo "=========================================="
echo ""
print_info "Istio Pods:"
kubectl -n "$ISTIO_NAMESPACE" get pods
echo ""
print_info "Mesh features active:"
echo "  - mTLS: STRICT (mesh-wide)"
echo "  - AuthorizationPolicy: Knative system access allowed"
echo "  - Gateway API: istio.io/gateway-controller"
echo ""
print_info "Next steps:"
print_info "  1. Remove Envoy Gateway:  ./components/events/envoy-gateway/scripts/destroy.sh"
print_info "  2. Verify mesh:           kubectl get pods -n $ISTIO_NAMESPACE"
print_info "  3. Check Gateway API:     kubectl get gateway -A"
