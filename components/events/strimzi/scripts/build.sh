#!/bin/bash
# Deploy Strimzi Kafka Operator + Kafka Cluster to the Kubernetes cluster using Helm
# Requires: Ceph deployed (for Kafka persistent storage on rook-ceph-block)
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
if ! kubectl get sc rook-ceph-block &>/dev/null; then
    print_error "StorageClass 'rook-ceph-block' not found"
    print_info "Deploy Ceph first: ./components/ceph/scripts/build.sh"
    exit 1
fi
print_success "  StorageClass rook-ceph-block available"

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
    deployment -l name=strimzi-cluster-operator --for=condition=Available

print_success "  Strimzi Operator deployed"

# ============================================================================
# STEP 3: Deploy Kafka Cluster (KRaft mode)
# ============================================================================
print_info "Step 3: Deploying Kafka cluster (${STRIMZI_KAFKA_CLUSTER_NAME})..."

kubectl apply -f "$COMPONENT_DIR/manifests/" -n "$STRIMZI_NAMESPACE"

# Wait for Kafka ready (takes 2-3 minutes)
print_info "  Waiting for Kafka cluster to be ready (this takes 2-3 minutes)..."
for i in {1..36}; do
    if kubectl get kafka "$STRIMZI_KAFKA_CLUSTER_NAME" -n "$STRIMZI_NAMESPACE" \
        -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q "True"; then
        break
    fi
    [[ "$i" -eq 36 ]] && { print_error "Kafka cluster not ready after 3 minutes"; exit 1; }
    sleep 5
done

print_success "  Kafka cluster deployed"

# ============================================================================
# STATUS
# ============================================================================
print_success "Strimzi Kafka Deployed!"
echo "=========================================="
echo ""
print_info "Strimzi Pods:"
kubectl -n "$STRIMZI_NAMESPACE" get pods
echo ""
print_info "Bootstrap: ${STRIMZI_KAFKA_CLUSTER_NAME}-kafka-bootstrap.${STRIMZI_NAMESPACE}.svc.cluster.local:9092"
echo ""
print_info "Next steps:"
print_info "  1. Deploy Knative:       ./components/events/knative/scripts/build.sh"
print_info "  2. Create topics:        kubectl apply -f <topic.yaml> -n $STRIMZI_NAMESPACE"
