#!/bin/bash
# Uninstall Envoy Gateway from the Kubernetes cluster
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

source "$PROJECT_ROOT/scripts/common/utils.sh"
source "$PROJECT_ROOT/scripts/common/config-loader.sh"

if ! kubectl cluster-info &>/dev/null; then
    print_error "Kubernetes cluster is not accessible"
    exit 1
fi

print_warning "This will completely remove Envoy Gateway!"
read -p "Are you sure? (y/N): " confirm

if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    print_info "Aborted."
    exit 0
fi

print_info "Removing Envoy Gateway..."
echo "=========================================="

# Step 1: Delete Gateway resource
print_info "Step 1: Deleting Gateway resources..."
kubectl delete gateway knative-gateway -n "$KNATIVE_SERVING_NAMESPACE" --ignore-not-found=true 2>/dev/null || true

# Step 2: Uninstall Helm release
print_info "Step 2: Uninstalling Helm release..."
if helm status envoy-gateway -n "$ENVOY_GATEWAY_NAMESPACE" &>/dev/null; then
    helm uninstall envoy-gateway -n "$ENVOY_GATEWAY_NAMESPACE" --timeout=120s 2>/dev/null || true
    print_success "  Helm release uninstalled"
else
    print_info "  Helm release not found, skipping"
fi

# Step 3: Delete Gateway API CRDs
print_info "Step 3: Deleting Gateway API CRDs..."
for crd in $(kubectl get crd -o name 2>/dev/null | grep -E 'gateway\.networking\.k8s\.io|gateway\.envoyproxy\.io'); do
    kubectl delete "$crd" --timeout=30s 2>/dev/null || true
done

# Step 4: Delete namespace
print_info "Step 4: Deleting namespace..."
if kubectl get namespace "$ENVOY_GATEWAY_NAMESPACE" &>/dev/null; then
    kubectl delete namespace "$ENVOY_GATEWAY_NAMESPACE" --timeout=60s 2>/dev/null || {
        print_warning "  Namespace stuck, removing finalizer..."
        kubectl get namespace "$ENVOY_GATEWAY_NAMESPACE" -o json \
            | python3 -c 'import sys,json; ns=json.load(sys.stdin); ns["spec"]["finalizers"]=[]; json.dump(ns,sys.stdout)' \
            | kubectl replace --raw "/api/v1/namespaces/$ENVOY_GATEWAY_NAMESPACE/finalize" -f - 2>/dev/null || true
    }
    print_success "  Namespace deleted"
fi

print_success "Envoy Gateway completely removed."
print_info "To redeploy: ./components/events/envoy-gateway/scripts/build.sh"
