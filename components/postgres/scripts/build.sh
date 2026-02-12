#!/bin/bash
# Deploy CloudNativePG Operator + Test PostgreSQL Cluster
# Follows Strimzi/Knative operator pattern
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
COMPONENT_DIR="$PROJECT_ROOT/components/postgres"
HELM_DIR="$COMPONENT_DIR/helm"

source "$PROJECT_ROOT/scripts/common/utils.sh"
source "$PROJECT_ROOT/scripts/common/config-loader.sh"

# Check if component is enabled
if [[ "$POSTGRES_ENABLED" != "true" ]]; then
    print_error "PostgreSQL is not enabled in config.yaml"
    print_info "Set 'components.postgres.enabled: true' in config.yaml"
    exit 1
fi

# Check if Kubernetes cluster is accessible
if ! kubectl cluster-info &>/dev/null; then
    print_error "Kubernetes cluster is not accessible"
    exit 1
fi

print_info "Deploying CloudNativePG (chart v${POSTGRES_CHART_VERSION})"
print_info "Namespace: $POSTGRES_NAMESPACE"
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
kubectl create namespace "$POSTGRES_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
print_success "  Namespace $POSTGRES_NAMESPACE ready"

# ============================================================================
# STEP 2: Install CloudNativePG Operator via Helm
# ============================================================================
print_info "Step 2: Installing CloudNativePG Operator..."

helm repo add cnpg "$POSTGRES_CHART_REPO" 2>/dev/null || true
helm repo update

print_info "  Updating chart dependencies..."
helm dependency update "$HELM_DIR"

HELM_CMD="helm upgrade --install postgres-operator $HELM_DIR \
    -n $POSTGRES_NAMESPACE \
    -f $HELM_DIR/values.yaml \
    -f $HELM_DIR/values-overrides.yaml \
    --wait --timeout=300s"

eval $HELM_CMD

print_info "  Waiting for CloudNativePG operator..."
kubectl wait --timeout=120s -n "$POSTGRES_NAMESPACE" \
    deployment -l app.kubernetes.io/name=cloudnative-pg --for=condition=Available

print_success "  CloudNativePG Operator deployed"

# ============================================================================
# STATUS
# ============================================================================
print_success "CloudNativePG Operator Deployed!"
echo "=========================================="
echo ""
print_info "Operator Pods:"
kubectl -n "$POSTGRES_NAMESPACE" get pods -l app.kubernetes.io/name=cloudnative-pg
echo ""
print_info "Next steps:"
print_info "  - Deploy test cluster: ./components/postgres/scripts/tests/deploy-test-cluster.sh"
print_info "  - Check operator status: kubectl get pods -n $POSTGRES_NAMESPACE"
print_info "  - View operator logs: kubectl logs -n $POSTGRES_NAMESPACE -l app.kubernetes.io/name=cloudnative-pg"

