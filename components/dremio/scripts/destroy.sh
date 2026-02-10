#!/bin/bash
# Uninstall Dremio from the Kubernetes cluster
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

source "$PROJECT_ROOT/scripts/common/utils.sh"
source "$PROJECT_ROOT/scripts/common/config-loader.sh"

if ! kubectl cluster-info &>/dev/null; then
    print_error "Kubernetes cluster is not accessible"
    exit 1
fi

print_warning "This will completely remove Dremio!"
read -p "Are you sure? (y/N): " confirm

if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    print_info "Aborted."
    exit 0
fi

print_info "Removing Dremio..."

# Step 1: Uninstall Helm release
print_info "Step 1: Uninstalling Helm release..."
if helm status dremio -n "$DREMIO_NAMESPACE" &>/dev/null; then
    helm uninstall dremio -n "$DREMIO_NAMESPACE" --timeout=120s 2>/dev/null || true
    print_success "  Helm release uninstalled"
else
    print_info "  Helm release not found, skipping"
fi

# Step 2: Delete PVCs
print_info "Step 2: Deleting PVCs..."
kubectl -n "$DREMIO_NAMESPACE" delete pvc --all --timeout=60s 2>/dev/null || true

# Step 3: Delete CRDs (engine operator CRD)
print_info "Step 3: Deleting Dremio CRDs..."
for crd in $(kubectl get crd -o name 2>/dev/null | grep -E 'dremio\.com|percona\.com|opster\.io'); do
    kubectl delete "$crd" --timeout=30s 2>/dev/null || true
done

# Step 4: Delete namespace
print_info "Step 4: Deleting namespace..."
if kubectl get namespace "$DREMIO_NAMESPACE" &>/dev/null; then
    kubectl delete namespace "$DREMIO_NAMESPACE" --timeout=60s 2>/dev/null || {
        print_warning "  Namespace stuck, removing finalizer..."
        kubectl get namespace "$DREMIO_NAMESPACE" -o json \
            | python3 -c 'import sys,json; ns=json.load(sys.stdin); ns["spec"]["finalizers"]=[]; json.dump(ns,sys.stdout)' \
            | kubectl replace --raw "/api/v1/namespaces/$DREMIO_NAMESPACE/finalize" -f - 2>/dev/null || true
    }
    print_success "  Namespace deleted"
fi

print_success "Dremio completely removed."
print_info "To redeploy: ./components/dremio/scripts/build.sh"
