#!/bin/bash
# Deploy Strimzi Kafka Operator to the Kubernetes cluster using Helm
# Requires: Ceph deployed (for Kafka persistent storage on ceph-block)
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
COMPONENT_DIR="$PROJECT_ROOT/components/events/strimzi"
HELM_DIR="$COMPONENT_DIR/helm"

source "$PROJECT_ROOT/scripts/common/utils.sh"
source "$PROJECT_ROOT/scripts/common/config-loader.sh"

# Check if component is enabled
if [[ "$STRIMZI_ENABLED" != "true" ]]; then
    print_error "Strimzi is not enabled in config.yaml"
    print_info "Set 'components.strimzi.enabled: true' in config.yaml"
    exit 1
fi

# Check if Kubernetes cluster is accessible
if ! kubectl cluster-info &>/dev/null; then
    print_error "Kubernetes cluster is not accessible"
    exit 1
fi

print_info "Deploying Strimzi Kafka (chart v${STRIMZI_CHART_VERSION}, Kafka ${STRIMZI_KAFKA_VERSION})"
print_info "Namespace: $STRIMZI_NAMESPACE"
echo "=========================================="

# ============================================================================
# PRE-FLIGHT: Verify Ceph StorageClass is available
# ============================================================================
print_info "Verifying Ceph StorageClass is available..."
if ! kubectl get sc ceph-block &>/dev/null; then
    print_error "StorageClass 'ceph-block' not found"
    print_info "Deploy Ceph first: ./components/ceph/scripts/build.sh"
    exit 1
fi
print_success "  StorageClass ceph-block available"

# ============================================================================
# STEP 1: Create namespace
# ============================================================================
print_info "Step 1: Creating namespace..."
kubectl create namespace "$STRIMZI_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
print_success "  Namespace $STRIMZI_NAMESPACE ready"

# ============================================================================
# STEP 2: Install Strimzi Operator via Helm
# ============================================================================
print_info "Step 2: Installing Strimzi Operator..."

helm repo add strimzi "$STRIMZI_CHART_REPO" 2>/dev/null || true
helm repo update

print_info "  Updating chart dependencies..."
helm dependency update "$HELM_DIR"

HELM_CMD="helm upgrade --install strimzi $HELM_DIR \
    -n $STRIMZI_NAMESPACE \
    -f $HELM_DIR/values.yaml \
    -f $HELM_DIR/values-overrides.yaml \
    --wait --timeout=300s"

eval $HELM_CMD

print_info "  Waiting for Strimzi operator..."
kubectl wait --timeout=120s -n "$STRIMZI_NAMESPACE" \
    deployment/strimzi-cluster-operator --for=condition=Available

print_success "  Strimzi Operator deployed"

# ============================================================================
# STATUS
# ============================================================================
print_success "Strimzi Operator Deployed!"
echo "=========================================="
echo ""
print_info "Operator Pods:"
kubectl -n "$STRIMZI_NAMESPACE" get pods
echo ""
print_info "Next steps:"
print_info "  1. Test (creates cluster, validates, tears down):"
print_info "     ./components/events/strimzi/scripts/test/test-kafka.sh"
