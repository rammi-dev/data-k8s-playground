#!/bin/bash
# Remove Camel K Operator and all integrations
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

source "$PROJECT_ROOT/scripts/common/utils.sh"
source "$PROJECT_ROOT/scripts/common/config-loader.sh"

NAMESPACE="${CAMEL_K_NAMESPACE:-camel-k}"

print_info "Destroying Camel K..."
echo "=========================================="

# Step 1: Delete all integrations and pipes across namespaces
print_info "Step 1: Deleting Integrations and Pipes..."
kubectl delete integrations --all -A --ignore-not-found=true 2>/dev/null || true
kubectl delete pipes --all -A --ignore-not-found=true 2>/dev/null || true
print_success "  Integrations and Pipes removed"

# Step 2: Uninstall Helm release
print_info "Step 2: Uninstalling Helm release..."
helm uninstall camel-k -n "$NAMESPACE" 2>/dev/null || true
print_success "  Helm release removed"

# Step 3: Remove CRDs
print_info "Step 3: Removing CRDs..."
kubectl delete crds -l app.kubernetes.io/name=camel-k --ignore-not-found=true 2>/dev/null || true
print_success "  CRDs removed"

# Step 4: Delete namespace
print_info "Step 4: Deleting namespace..."
kubectl delete namespace "$NAMESPACE" --ignore-not-found=true 2>/dev/null || true
print_success "  Namespace removed"

print_success "Camel K destroyed"
