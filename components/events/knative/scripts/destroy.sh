#!/bin/bash
# Uninstall Knative Serving + Eventing from the Kubernetes cluster
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

source "$PROJECT_ROOT/scripts/common/utils.sh"
source "$PROJECT_ROOT/scripts/common/config-loader.sh"

if ! kubectl cluster-info &>/dev/null; then
    print_error "Kubernetes cluster is not accessible"
    exit 1
fi

print_warning "This will completely remove Knative Serving + Eventing!"
read -p "Are you sure? (y/N): " confirm

if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    print_info "Aborted."
    exit 0
fi

print_info "Removing Knative..."
echo "=========================================="

# Step 1: Delete demo resources
print_info "Step 1: Deleting demo resources..."
kubectl delete namespace eventing-demo --ignore-not-found=true --timeout=60s 2>/dev/null || true
kubectl delete ksvc hello -n default --ignore-not-found=true 2>/dev/null || true

# Step 2: Delete KnativeEventing CR
print_info "Step 2: Deleting KnativeEventing CR..."
kubectl delete knativeeventing knative-eventing -n "$KNATIVE_EVENTING_NAMESPACE" --timeout=120s 2>/dev/null || true
kubectl delete configmap kafka-broker-config -n "$KNATIVE_EVENTING_NAMESPACE" --ignore-not-found=true 2>/dev/null || true
print_success "  KnativeEventing deleted"

# Step 3: Delete KnativeServing CR
print_info "Step 3: Deleting KnativeServing CR..."
kubectl delete knativeserving knative-serving -n "$KNATIVE_SERVING_NAMESPACE" --timeout=120s 2>/dev/null || true
print_success "  KnativeServing deleted"

# Step 4: Uninstall Helm release (operator)
print_info "Step 4: Uninstalling Helm release..."
if helm status knative-operator -n "$KNATIVE_NAMESPACE" &>/dev/null; then
    helm uninstall knative-operator -n "$KNATIVE_NAMESPACE" --timeout=120s 2>/dev/null || true
    print_success "  Helm release uninstalled"
else
    print_info "  Helm release not found, skipping"
fi

# Step 5: Delete CRDs
print_info "Step 5: Deleting Knative CRDs..."
for crd in $(kubectl get crd -o name 2>/dev/null | grep -E 'knative\.dev|operator\.knative\.dev'); do
    kubectl delete "$crd" --timeout=30s 2>/dev/null || true
done

# Step 6: Delete namespaces
print_info "Step 6: Deleting namespaces..."
for ns in "$KNATIVE_EVENTING_NAMESPACE" "$KNATIVE_SERVING_NAMESPACE" "$KNATIVE_NAMESPACE"; do
    if kubectl get namespace "$ns" &>/dev/null; then
        kubectl delete namespace "$ns" --timeout=60s 2>/dev/null || {
            print_warning "  Namespace $ns stuck, removing finalizer..."
            kubectl get namespace "$ns" -o json \
                | python3 -c 'import sys,json; ns=json.load(sys.stdin); ns["spec"]["finalizers"]=[]; json.dump(ns,sys.stdout)' \
                | kubectl replace --raw "/api/v1/namespaces/$ns/finalize" -f - 2>/dev/null || true
        }
        print_success "  Namespace $ns deleted"
    fi
done

print_success "Knative completely removed."
print_info "To redeploy: ./components/events/knative/scripts/build.sh"
