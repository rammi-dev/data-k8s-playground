#!/bin/bash
# Remove Apache Spark Kubernetes Operator from the Kubernetes cluster
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

RELEASE_NAME="spark-apache"

print_info "Removing Apache Spark Kubernetes Operator"
echo "=========================================="

# Uninstall Helm release
if helm status ${RELEASE_NAME} -n "${SPARK_APACHE_NAMESPACE}" &>/dev/null; then
    print_info "Uninstalling Spark Apache Operator..."
    helm uninstall ${RELEASE_NAME} -n "${SPARK_APACHE_NAMESPACE}"
else
    print_info "Spark Apache Operator not found, skipping..."
fi

# Delete PVCs
print_info "Deleting persistent volume claims..."
kubectl delete pvc --all -n "${SPARK_APACHE_NAMESPACE}" --ignore-not-found=true

# Delete namespaces (operator + workload)
for ns in "${SPARK_APACHE_NAMESPACE}" "spark-workload"; do
    print_info "Deleting namespace: ${ns}"
    kubectl delete namespace "${ns}" --ignore-not-found=true
done

print_success "Apache Spark Kubernetes Operator Removed!"
