#!/bin/bash
# Remove Apache Airflow from the Kubernetes cluster
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

source "$PROJECT_ROOT/scripts/common/utils.sh"
source "$PROJECT_ROOT/scripts/common/config-loader.sh"

RELEASE_NAME="airflow"

print_info "Removing Apache Airflow"
echo "=========================================="

# Uninstall Helm release
if helm status ${RELEASE_NAME} -n "${AIRFLOW_NAMESPACE}" &>/dev/null; then
    print_info "Uninstalling Airflow..."
    helm uninstall ${RELEASE_NAME} -n "${AIRFLOW_NAMESPACE}"
else
    print_info "Airflow not found, skipping..."
fi

# Delete PVCs
print_info "Deleting persistent volume claims..."
kubectl delete pvc --all -n "${AIRFLOW_NAMESPACE}" --ignore-not-found=true

# Delete namespace
print_info "Deleting namespace: ${AIRFLOW_NAMESPACE}"
kubectl delete namespace "${AIRFLOW_NAMESPACE}" --ignore-not-found=true

print_success "Apache Airflow Removed!"
