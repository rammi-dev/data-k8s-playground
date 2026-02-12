#!/bin/bash
# Deploy Apache Airflow to the Kubernetes cluster using Helm
set -e

# Determine project root (works from any location)
if [[ -d "/vagrant" ]]; then
    PROJECT_ROOT="/vagrant"
elif [[ -n "${PROJECT_ROOT:-}" ]]; then
    : # Use existing PROJECT_ROOT
else
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
fi

COMPONENT_DIR="$PROJECT_ROOT/components/airflow"
HELM_DIR="$COMPONENT_DIR/helm"

source "$PROJECT_ROOT/scripts/common/utils.sh"
source "$PROJECT_ROOT/scripts/common/config-loader.sh"

RELEASE_NAME="airflow"

# Check if component is enabled
if [[ "$AIRFLOW_ENABLED" != "true" ]]; then
    print_error "Airflow is not enabled in config.yaml"
    print_info "Set 'components.airflow.enabled: true' in config.yaml"
    exit 1
fi

# Check if Kubernetes cluster is accessible
if ! kubectl cluster-info &>/dev/null; then
    print_error "Kubernetes cluster is not accessible"
    print_info "Make sure kubectl is configured and the cluster is running"
    exit 1
fi

print_info "Deploying Apache Airflow (chart v${AIRFLOW_CHART_VERSION})"
echo "=========================================="

# Create namespace if it doesn't exist
print_info "Creating namespace: ${AIRFLOW_NAMESPACE}"
kubectl create namespace "${AIRFLOW_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

# Add Airflow Helm repository
print_info "Adding Apache Airflow Helm repository..."
helm repo add apache-airflow "$AIRFLOW_CHART_REPO" 2>/dev/null || true
helm repo update

# Update chart dependencies
print_info "Updating chart dependencies..."
helm dependency update "$HELM_DIR"

# Install or upgrade Airflow
print_info "Installing/upgrading Apache Airflow..."
helm upgrade --install ${RELEASE_NAME} "$HELM_DIR" \
    --namespace "${AIRFLOW_NAMESPACE}" \
    --values "$HELM_DIR/values.yaml" \
    --timeout 600s

print_info "Waiting for pods to be ready..."
kubectl wait --for=condition=ready pod -l release=${RELEASE_NAME} -n "${AIRFLOW_NAMESPACE}" --timeout=300s || true

print_success "Apache Airflow Deployed!"
echo "=========================================="

echo ""
print_info "Installed Components:"
echo "  - Webserver: Airflow UI"
echo "  - Scheduler: DAG scheduling"
echo "  - Triggerer: Async trigger handling"
echo "  - PostgreSQL: Metadata database"

echo ""
print_info "To access Airflow Webserver, run:"
echo "  ${COMPONENT_DIR}/scripts/access-webserver.sh"

echo ""
print_info "To upgrade: edit helm/values.yaml and re-run this script"
