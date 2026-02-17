#!/bin/bash
# Uninstall Apicurio Registry from the Kubernetes cluster
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

source "$PROJECT_ROOT/scripts/common/utils.sh"
source "$PROJECT_ROOT/scripts/common/config-loader.sh"

if ! kubectl cluster-info &>/dev/null; then
    print_error "Kubernetes cluster is not accessible"
    exit 1
fi

print_warning "This will remove Apicurio Registry (deployment + service)!"
print_warning "The kafkasql-journal topic in Kafka will NOT be deleted."
read -p "Are you sure? (y/N): " confirm

if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    print_info "Aborted."
    exit 0
fi

print_info "Removing Apicurio Registry..."
echo "=========================================="

# Step 1: Delete Deployment
print_info "Step 1: Deleting Apicurio Registry deployment..."
kubectl delete deployment apicurio-registry -n "$APICURIO_NAMESPACE" --timeout=60s 2>/dev/null || true
print_success "  Deployment deleted"

# Step 2: Delete Service
print_info "Step 2: Deleting Apicurio Registry service..."
kubectl delete service apicurio-registry -n "$APICURIO_NAMESPACE" --timeout=30s 2>/dev/null || true
print_success "  Service deleted"

# Note: We do NOT delete the namespace (shared with Strimzi Kafka)
# Note: We do NOT delete the kafkasql-journal Kafka topic (data preservation)

print_success "Apicurio Registry removed."
print_info "Kafka topic 'kafkasql-journal' still exists (schema data preserved)."
print_info "To delete it: kubectl delete kafkatopic kafkasql-journal -n $STRIMZI_NAMESPACE"
print_info "To redeploy:  ./components/events/apicurio/scripts/build.sh"
