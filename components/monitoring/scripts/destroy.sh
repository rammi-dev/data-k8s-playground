#!/bin/bash
# Remove monitoring stack
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../scripts/common/utils.sh"

NAMESPACE="monitoring"
RELEASE_NAME="loki"

print_info "Removing Monitoring Stack"
echo "=========================================="

# Uninstall Helm release
if helm status ${RELEASE_NAME} -n ${NAMESPACE} &>/dev/null; then
    print_info "Uninstalling Loki stack..."
    helm uninstall ${RELEASE_NAME} -n ${NAMESPACE}
else
    print_info "Loki stack not found, skipping..."
fi

# Delete PVCs
print_info "Deleting persistent volume claims..."
kubectl delete pvc --all -n ${NAMESPACE} --ignore-not-found=true

# Delete namespace
print_info "Deleting namespace: ${NAMESPACE}"
kubectl delete namespace ${NAMESPACE} --ignore-not-found=true

print_success "Monitoring Stack Removed!"
