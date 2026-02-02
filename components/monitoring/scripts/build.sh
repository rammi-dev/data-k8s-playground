#!/bin/bash
# Deploy monitoring stack (Loki + Grafana + Prometheus + Promtail)
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPONENT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/../../../scripts/common/utils.sh"

NAMESPACE="monitoring"
RELEASE_NAME="loki"

# Read loki-stack chart version from Chart.yaml dependencies
CHART_VERSION=$(grep -A2 'name: loki-stack' "${COMPONENT_DIR}/helm/Chart.yaml" | grep 'version:' | awk '{print $2}' | tr -d '"')

print_info "Deploying Monitoring Stack (loki-stack v${CHART_VERSION})"
echo "=========================================="

# Create namespace if it doesn't exist
print_info "Creating namespace: ${NAMESPACE}"
kubectl create namespace ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

# Add Grafana Helm repository
print_info "Adding Grafana Helm repository..."
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# Install or upgrade Loki stack
if helm status ${RELEASE_NAME} -n ${NAMESPACE} &>/dev/null; then
    print_info "Upgrading existing Loki stack..."
    helm upgrade ${RELEASE_NAME} grafana/loki-stack \
        --version "${CHART_VERSION}" \
        --namespace ${NAMESPACE} \
        --values "${COMPONENT_DIR}/helm/values.yaml"
else
    print_info "Installing Loki stack (Loki + Grafana + Prometheus + Promtail)..."
    helm install ${RELEASE_NAME} grafana/loki-stack \
        --version "${CHART_VERSION}" \
        --namespace ${NAMESPACE} \
        --values "${COMPONENT_DIR}/helm/values.yaml"
fi

print_info "Waiting for pods to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=${RELEASE_NAME} -n ${NAMESPACE} --timeout=300s || true

print_success "Monitoring Stack Deployed!"
echo "=========================================="

# Get Grafana admin password
GRAFANA_PASSWORD=$(kubectl get secret --namespace ${NAMESPACE} ${RELEASE_NAME}-grafana -o jsonpath="{.data.admin-password}" | base64 --decode)

echo ""
print_info "Grafana Admin Credentials:"
echo "  Username: admin"
echo "  Password: ${GRAFANA_PASSWORD}"

echo ""
print_info "Installed Components:"
echo "  - Loki: Log aggregation"
echo "  - Grafana: Visualization & Dashboards"
echo "  - Prometheus: Metrics collection"
echo "  - Promtail: Log collection"

echo ""
print_info "Dashboards Available:"
echo "  - Kubernetes Cluster Overview"
echo "  - Node Monitoring"
echo "  - Workload Monitoring (Deployments/StatefulSets)"
echo "  - Pod Monitoring"
echo "  - Persistent Volumes"
echo "  - Namespaces Overview"

echo ""
print_info "To access Grafana, run:"
echo "  ${SCRIPT_DIR}/access-grafana.sh"
