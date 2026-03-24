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

# ============================================================================
# STEP 1: Ensure CloudNative-PG operator is deployed (reuse postgres component)
# ============================================================================
print_info "Checking CloudNative-PG operator..."
if ! kubectl get deployment -n "${POSTGRES_NAMESPACE}" -l app.kubernetes.io/name=cloudnative-pg --no-headers 2>/dev/null | grep -q .; then
    print_info "CNPG operator not found — deploying via postgres build script..."
    bash "$PROJECT_ROOT/components/postgres/scripts/build.sh"
else
    print_success "CNPG operator already running, skipping install"
fi

# ============================================================================
# STEP 2: Deploy Airflow metadata DB (CNPG Cluster CR)
# ============================================================================
print_info "Applying Airflow DB credentials secret..."
kubectl apply -f "$HELM_DIR/airflow-db-secret.yaml"

print_info "Applying Airflow DB CNPG cluster..."
kubectl apply -f "$HELM_DIR/airflow-db-cluster.yaml"

print_info "Waiting for Airflow DB cluster to be ready (up to 3 min)..."
kubectl wait cluster/airflow-db -n "${AIRFLOW_NAMESPACE}" \
    --for=condition=Ready --timeout=180s || \
    print_info "DB cluster not yet Ready, continuing (check: kubectl get cluster airflow-db -n ${AIRFLOW_NAMESPACE})"

# ============================================================================
# STEP 3: Pre-create the DAGs PVC (CephFS RWX)
# ============================================================================
print_info "Ensuring DAGs PVC exists (airflow-dags on ceph-filesystem)..."
kubectl apply -f "$HELM_DIR/dags-pvc.yaml"

print_info "Waiting for DAGs PVC to bind..."
kubectl wait --for=jsonpath='{.status.phase}'=Bound pvc/airflow-dags -n "${AIRFLOW_NAMESPACE}" --timeout=60s || \
    print_info "PVC not yet Bound, continuing"

# ============================================================================
# STEP 4: Deploy Airflow via Helm
# ============================================================================
print_info "Adding Apache Airflow Helm repository..."
helm repo add apache-airflow "$AIRFLOW_CHART_REPO" 2>/dev/null || true
helm repo update

print_info "Updating chart dependencies..."
helm dependency update "$HELM_DIR"

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
