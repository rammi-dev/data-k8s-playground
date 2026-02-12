#!/bin/bash
# Uninstall Istio service mesh from the Kubernetes cluster
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

source "$PROJECT_ROOT/scripts/common/utils.sh"
source "$PROJECT_ROOT/scripts/common/config-loader.sh"

if ! kubectl cluster-info &>/dev/null; then
    print_error "Kubernetes cluster is not accessible"
    exit 1
fi

print_warning "This will completely remove Istio service mesh!"
read -p "Are you sure? (y/N): " confirm

if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    print_info "Aborted."
    exit 0
fi

print_info "Removing Istio..."
echo "=========================================="

# Step 1: Remove sidecar injection labels
print_info "Step 1: Removing sidecar injection labels..."
for ns in default eventing-demo; do
    kubectl label namespace "$ns" istio-injection- 2>/dev/null || true
done

# Step 2: Delete mesh policies
print_info "Step 2: Deleting mesh policies..."
kubectl delete authorizationpolicy --all -n default --ignore-not-found=true 2>/dev/null || true
kubectl delete authorizationpolicy --all -n eventing-demo --ignore-not-found=true 2>/dev/null || true
kubectl delete peerauthentication --all -n "$ISTIO_NAMESPACE" --ignore-not-found=true 2>/dev/null || true

# Step 3: Delete Kiali/Jaeger addons if installed
print_info "Step 3: Deleting observability addons..."
kubectl delete deployment kiali -n "$ISTIO_NAMESPACE" --ignore-not-found=true 2>/dev/null || true
kubectl delete deployment jaeger -n "$ISTIO_NAMESPACE" --ignore-not-found=true 2>/dev/null || true

# Step 4: Uninstall Helm release
print_info "Step 4: Uninstalling Helm release..."
if helm status istio -n "$ISTIO_NAMESPACE" &>/dev/null; then
    helm uninstall istio -n "$ISTIO_NAMESPACE" --timeout=120s 2>/dev/null || true
    print_success "  Helm release uninstalled"
else
    print_info "  Helm release not found, skipping"
fi

# Step 5: Delete CRDs
print_info "Step 5: Deleting Istio CRDs..."
for crd in $(kubectl get crd -o name 2>/dev/null | grep -E 'istio\.io|security\.istio\.io|networking\.istio\.io|telemetry\.istio\.io'); do
    kubectl delete "$crd" --timeout=30s 2>/dev/null || true
done

# Step 6: Delete namespace
print_info "Step 6: Deleting namespace..."
if kubectl get namespace "$ISTIO_NAMESPACE" &>/dev/null; then
    kubectl delete namespace "$ISTIO_NAMESPACE" --timeout=60s 2>/dev/null || {
        print_warning "  Namespace stuck, removing finalizer..."
        kubectl get namespace "$ISTIO_NAMESPACE" -o json \
            | python3 -c 'import sys,json; ns=json.load(sys.stdin); ns["spec"]["finalizers"]=[]; json.dump(ns,sys.stdout)' \
            | kubectl replace --raw "/api/v1/namespaces/$ISTIO_NAMESPACE/finalize" -f - 2>/dev/null || true
    }
    print_success "  Namespace deleted"
fi

# Step 7: Restart workloads to remove sidecars
print_info "Step 7: Restarting workloads to remove sidecars..."
for ns in default eventing-demo; do
    if kubectl get namespace "$ns" &>/dev/null; then
        kubectl rollout restart deployment -n "$ns" 2>/dev/null || true
    fi
done

print_success "Istio completely removed."
print_info "To redeploy: ./components/events/istio/scripts/build.sh"
