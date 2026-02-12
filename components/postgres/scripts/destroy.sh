#!/bin/bash
# Completely remove CloudNativePG operator and all PostgreSQL clusters
# Removes: clusters, operator, CRDs, namespace, and PVCs
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

source "$PROJECT_ROOT/scripts/common/utils.sh"
source "$PROJECT_ROOT/scripts/common/config-loader.sh"

# Check if Kubernetes cluster is accessible
if ! kubectl cluster-info &>/dev/null; then
    print_error "Kubernetes cluster is not accessible"
    exit 1
fi

print_warning "This will completely remove CloudNativePG (operator + all databases)!"
read -p "Are you sure? (y/N): " confirm

if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    print_info "Aborted."
    exit 0
fi

print_info "Removing CloudNativePG..."

# Helper: remove finalizers from all objects of a given CRD in the namespace
remove_finalizers() {
    local crd="$1"
    for obj in $(kubectl -n "$POSTGRES_NAMESPACE" get "$crd" -o name 2>/dev/null); do
        print_info "  Removing finalizers from $obj..."
        kubectl -n "$POSTGRES_NAMESPACE" patch "$obj" --type merge -p '{"metadata":{"finalizers":null}}' 2>/dev/null || true
    done
}

# Step 1: Delete all PostgreSQL Cluster CRs
print_info "Step 1: Deleting PostgreSQL clusters..."
if kubectl get crd clusters.postgresql.cnpg.io &>/dev/null; then
    remove_finalizers "clusters.postgresql.cnpg.io"
    kubectl -n "$POSTGRES_NAMESPACE" delete clusters.postgresql.cnpg.io --all --timeout=60s 2>/dev/null || true
    print_success "  Clusters deleted"
else
    print_info "  No clusters found"
fi

# Step 2: Delete PVCs
print_info "Step 2: Deleting PVCs..."
kubectl -n "$POSTGRES_NAMESPACE" delete pvc --all --timeout=30s 2>/dev/null || true
print_success "  PVCs deleted"

# Step 3: Uninstall Helm release
print_info "Step 3: Uninstalling CloudNativePG operator..."
if helm status postgres-operator -n "$POSTGRES_NAMESPACE" &>/dev/null; then
    helm uninstall postgres-operator -n "$POSTGRES_NAMESPACE" --timeout=60s 2>/dev/null || true
    print_success "  Operator uninstalled"
else
    print_info "  Operator not installed"
fi

# Step 4: Delete namespace
print_info "Step 4: Deleting namespace..."
if kubectl get namespace "$POSTGRES_NAMESPACE" &>/dev/null; then
    kubectl delete namespace "$POSTGRES_NAMESPACE" --timeout=60s 2>/dev/null || {
        # Namespace stuck in Terminating - force-remove the kubernetes finalizer
        print_warning "  Namespace stuck in Terminating, removing finalizer..."
        kubectl get namespace "$POSTGRES_NAMESPACE" -o json \
            | python3 -c 'import sys,json; ns=json.load(sys.stdin); ns["spec"]["finalizers"]=[]; json.dump(ns,sys.stdout)' \
            | kubectl replace --raw "/api/v1/namespaces/$POSTGRES_NAMESPACE/finalize" -f - 2>/dev/null || true
        # Wait for namespace to disappear
        for i in $(seq 1 12); do
            kubectl get namespace "$POSTGRES_NAMESPACE" &>/dev/null || break
            sleep 5
        done
    }
    print_success "  Namespace deleted"
else
    print_info "  Namespace not found"
fi

# Step 5: Delete CRDs
print_info "Step 5: Deleting CloudNativePG CRDs..."
for crd in $(kubectl get crd -o name 2>/dev/null | grep 'postgresql.cnpg.io'); do
    kubectl delete "$crd" --timeout=30s 2>/dev/null || true
done
print_success "  CRDs deleted"

print_success "CloudNativePG completely removed."
print_info "To redeploy: ./components/postgres/scripts/build.sh"
