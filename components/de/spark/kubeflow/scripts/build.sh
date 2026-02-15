#!/bin/bash
# Deploy Kubeflow Spark Operator using Helm
set -e

# Determine project root (works from any location)
if [[ -d "/vagrant" ]]; then
    PROJECT_ROOT="/vagrant"
elif [[ -n "${PROJECT_ROOT:-}" ]]; then
    : # Use existing PROJECT_ROOT
else
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../../.." && pwd)"
fi

COMPONENT_DIR="$PROJECT_ROOT/components/de/spark/kubeflow"
HELM_DIR="$COMPONENT_DIR/helm"

source "$PROJECT_ROOT/scripts/common/utils.sh"
source "$PROJECT_ROOT/scripts/common/config-loader.sh"

RELEASE_NAME="spark-kubeflow"

# Check if component is enabled
if [[ "$SPARK_KUBEFLOW_ENABLED" != "true" ]]; then
    print_error "Spark Kubeflow Operator is not enabled in config.yaml"
    print_info "Set 'components.spark_kubeflow.enabled: true' in config.yaml"
    exit 1
fi

# Check if Kubernetes cluster is accessible
if ! kubectl cluster-info &>/dev/null; then
    print_error "Kubernetes cluster is not accessible"
    print_info "Make sure kubectl is configured and the cluster is running"
    exit 1
fi

print_info "Deploying Kubeflow Spark Operator (chart v${SPARK_KUBEFLOW_CHART_VERSION})"
echo "=========================================="

# Create namespace if it doesn't exist
print_info "Creating namespace: ${SPARK_KUBEFLOW_NAMESPACE}"
kubectl create namespace "${SPARK_KUBEFLOW_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

# Add Helm repository
print_info "Adding Kubeflow Spark Operator Helm repository..."
helm repo add spark-kubeflow "$SPARK_KUBEFLOW_CHART_REPO" 2>/dev/null || true
helm repo update

# Update chart dependencies
print_info "Updating chart dependencies..."
helm dependency update "$HELM_DIR"

# Install or upgrade
print_info "Installing/upgrading Kubeflow Spark Operator..."
helm upgrade --install ${RELEASE_NAME} "$HELM_DIR" \
    --namespace "${SPARK_KUBEFLOW_NAMESPACE}" \
    --values "$HELM_DIR/values.yaml" \
    --timeout 300s

print_info "Waiting for operator to be ready..."
kubectl wait --for=condition=Available deployment -l app.kubernetes.io/instance=${RELEASE_NAME} \
    -n "${SPARK_KUBEFLOW_NAMESPACE}" --timeout=120s || true

print_success "Kubeflow Spark Operator Deployed!"
echo "=========================================="

echo ""
print_info "Operator Pods:"
kubectl get pods -n "${SPARK_KUBEFLOW_NAMESPACE}"

echo ""
print_info "To submit a SparkApplication, create a manifest and run:"
echo "  kubectl apply -f <spark-app.yaml> -n ${SPARK_KUBEFLOW_NAMESPACE}"
