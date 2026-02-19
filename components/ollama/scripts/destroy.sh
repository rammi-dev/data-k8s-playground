#!/bin/bash
# Remove Ollama from the Kubernetes cluster
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

RELEASE_NAME="ollama"

print_info "Removing Ollama"
echo "=========================================="

# Uninstall Helm release
if helm status ${RELEASE_NAME} -n "${OLLAMA_NAMESPACE}" &>/dev/null; then
    print_info "Uninstalling Ollama..."
    helm uninstall ${RELEASE_NAME} -n "${OLLAMA_NAMESPACE}"
else
    print_info "Ollama not found, skipping..."
fi

# Delete PVCs (model storage)
print_info "Deleting persistent volume claims..."
kubectl delete pvc --all -n "${OLLAMA_NAMESPACE}" --ignore-not-found=true

# Delete namespace
print_info "Deleting namespace: ${OLLAMA_NAMESPACE}"
kubectl delete namespace "${OLLAMA_NAMESPACE}" --ignore-not-found=true

print_success "Ollama Removed!"
