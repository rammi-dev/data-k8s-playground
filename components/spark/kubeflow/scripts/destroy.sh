#!/bin/bash
# Remove Kubeflow Spark Operator from the Kubernetes cluster
set -e

# Determine project root (works from any location)
if [[ -d "/vagrant" ]]; then
    PROJECT_ROOT="/vagrant"
elif [[ -n "${PROJECT_ROOT:-}" ]]; then
    : # Use existing PROJECT_ROOT
else
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
fi

source "$PROJECT_ROOT/scripts/common/utils.sh"
source "$PROJECT_ROOT/scripts/common/config-loader.sh"

RELEASE_NAME="spark-kubeflow"

print_info "Removing Kubeflow Spark Operator"
echo "=========================================="

# Uninstall Helm release
if helm status ${RELEASE_NAME} -n "${SPARK_KUBEFLOW_NAMESPACE}" &>/dev/null; then
    print_info "Uninstalling Spark Kubeflow Operator..."
    helm uninstall ${RELEASE_NAME} -n "${SPARK_KUBEFLOW_NAMESPACE}"
else
    print_info "Spark Kubeflow Operator not found, skipping..."
fi

# Delete PVCs
print_info "Deleting persistent volume claims..."
kubectl delete pvc --all -n "${SPARK_KUBEFLOW_NAMESPACE}" --ignore-not-found=true

# Delete namespace
print_info "Deleting namespace: ${SPARK_KUBEFLOW_NAMESPACE}"
kubectl delete namespace "${SPARK_KUBEFLOW_NAMESPACE}" --ignore-not-found=true

print_success "Kubeflow Spark Operator Removed!"
