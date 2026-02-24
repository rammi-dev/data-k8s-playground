#!/bin/bash
# Deploy Apache Camel K Operator to the Kubernetes cluster using Helm
# Requires: Knative Serving + Eventing deployed (for Knative integration traits)
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
COMPONENT_DIR="$PROJECT_ROOT/components/events/camel-k"
HELM_DIR="$COMPONENT_DIR/helm"

source "$PROJECT_ROOT/scripts/common/utils.sh"
source "$PROJECT_ROOT/scripts/common/config-loader.sh"

# Check if component is enabled
if [[ "$CAMEL_K_ENABLED" != "true" ]]; then
    print_error "Camel K is not enabled in config.yaml"
    print_info "Set 'components.camel_k.enabled: true' in config.yaml"
    exit 1
fi

# Check if Kubernetes cluster is accessible
if ! kubectl cluster-info &>/dev/null; then
    print_error "Kubernetes cluster is not accessible"
    exit 1
fi

print_info "Deploying Camel K Operator (chart v${CAMEL_K_CHART_VERSION})"
print_info "Namespace: $CAMEL_K_NAMESPACE"
echo "=========================================="

# ============================================================================
# STEP 1: Create namespace
# ============================================================================
print_info "Step 1: Creating namespace..."
kubectl create namespace "$CAMEL_K_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
print_success "  Namespace $CAMEL_K_NAMESPACE ready"

# ============================================================================
# STEP 2: Install Camel K Operator via Helm
# ============================================================================
print_info "Step 2: Installing Camel K Operator..."

helm repo add camel-k "$CAMEL_K_CHART_REPO" 2>/dev/null || true
helm repo update

print_info "  Updating chart dependencies..."
helm dependency update "$HELM_DIR"

HELM_CMD="helm upgrade --install camel-k $HELM_DIR \
    -n $CAMEL_K_NAMESPACE \
    -f $HELM_DIR/values.yaml \
    -f $HELM_DIR/values-overrides.yaml \
    --wait --timeout=300s"

eval $HELM_CMD

print_info "  Waiting for Camel K operator..."
kubectl wait --timeout=120s -n "$CAMEL_K_NAMESPACE" \
    deployment/camel-k-operator --for=condition=Available

print_success "  Camel K Operator deployed"

# ============================================================================
# STEP 3: Create IntegrationPlatform and wait for Ready
# ============================================================================
print_info "Step 3: Creating IntegrationPlatform..."

# Discover the minikube registry ClusterIP (used for both Jib push and containerd pull)
REGISTRY_IP=$(kubectl get svc registry -n kube-system \
    -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "")
if [[ -z "$REGISTRY_IP" ]]; then
    print_error "  minikube registry addon not found"
    print_info "  Enable it: minikube addons enable registry"
    exit 1
fi
print_info "  Using registry at $REGISTRY_IP (ClusterIP)"

kubectl apply -n "$CAMEL_K_NAMESPACE" -f - <<EOF
apiVersion: camel.apache.org/v1
kind: IntegrationPlatform
metadata:
  name: camel-k
spec:
  build:
    publishStrategy: Jib
    registry:
      address: "${REGISTRY_IP}"
      insecure: true
EOF

print_info "  Waiting for IntegrationPlatform to become Ready..."
for i in $(seq 1 30); do
    PHASE=$(kubectl get integrationplatform camel-k -n "$CAMEL_K_NAMESPACE" \
        -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
    if [[ "$PHASE" == "Ready" ]]; then break; fi
    sleep 5
done

if [[ "$PHASE" == "Ready" ]]; then
    print_success "  IntegrationPlatform ready"
else
    print_error "  IntegrationPlatform not ready (phase: $PHASE)"
    print_info "  Check: kubectl get integrationplatform -n $CAMEL_K_NAMESPACE -o yaml"
    exit 1
fi

# ============================================================================
# STATUS
# ============================================================================
print_success "Camel K Operator Deployed!"
echo "=========================================="
echo ""
print_info "Operator Pods:"
kubectl -n "$CAMEL_K_NAMESPACE" get pods
echo ""
print_info "CRDs registered:"
kubectl get crds | grep camel || true
echo ""
print_info "Next steps:"
print_info "  1. Deploy the file dispatcher integration:"
print_info "     kubectl apply -f components/events/camel-k/manifests/"
print_info "  2. Test: ./components/events/camel-k/scripts/test/test-camel-k.sh"
