#!/bin/bash
# Uninstall Strimzi Kafka from the Kubernetes cluster
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

source "$PROJECT_ROOT/scripts/common/utils.sh"
source "$PROJECT_ROOT/scripts/common/config-loader.sh"

if ! kubectl cluster-info &>/dev/null; then
    print_error "Kubernetes cluster is not accessible"
    exit 1
fi

print_warning "This will completely remove Strimzi Kafka (operator + cluster + data)!"
read -p "Are you sure? (y/N): " confirm

if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    print_info "Aborted."
    exit 0
fi

print_info "Removing Strimzi Kafka..."
echo "=========================================="

# Step 1: Delete Kafka cluster CR (triggers operator cleanup)
print_info "Step 1: Deleting Kafka cluster..."
kubectl delete kafka "$STRIMZI_KAFKA_CLUSTER_NAME" -n "$STRIMZI_NAMESPACE" --timeout=120s 2>/dev/null || true
kubectl delete kafkanodepool --all -n "$STRIMZI_NAMESPACE" --timeout=60s 2>/dev/null || true
print_success "  Kafka cluster deleted"

# Step 2: Uninstall Helm release (operator)
print_info "Step 2: Uninstalling Helm release..."
if helm status strimzi -n "$STRIMZI_NAMESPACE" &>/dev/null; then
    helm uninstall strimzi -n "$STRIMZI_NAMESPACE" --timeout=120s 2>/dev/null || true
    print_success "  Helm release uninstalled"
else
    print_info "  Helm release not found, skipping"
fi

# Step 3: Delete PVCs
print_info "Step 3: Deleting PVCs..."
kubectl -n "$STRIMZI_NAMESPACE" delete pvc --all --timeout=60s 2>/dev/null || true

# Step 4: Delete CRDs
print_info "Step 4: Deleting Strimzi CRDs..."
for crd in $(kubectl get crd -o name 2>/dev/null | grep -E 'strimzi\.io'); do
    kubectl delete "$crd" --timeout=30s 2>/dev/null || true
done

# Step 5: Delete namespace
print_info "Step 5: Deleting namespace..."
if kubectl get namespace "$STRIMZI_NAMESPACE" &>/dev/null; then
    kubectl delete namespace "$STRIMZI_NAMESPACE" --timeout=60s 2>/dev/null || {
        print_warning "  Namespace stuck, removing finalizer..."
        kubectl get namespace "$STRIMZI_NAMESPACE" -o json \
            | python3 -c 'import sys,json; ns=json.load(sys.stdin); ns["spec"]["finalizers"]=[]; json.dump(ns,sys.stdout)' \
            | kubectl replace --raw "/api/v1/namespaces/$STRIMZI_NAMESPACE/finalize" -f - 2>/dev/null || true
    }
    print_success "  Namespace deleted"
fi

print_success "Strimzi Kafka completely removed."
print_info "To redeploy: ./components/events/strimzi/scripts/build.sh"
