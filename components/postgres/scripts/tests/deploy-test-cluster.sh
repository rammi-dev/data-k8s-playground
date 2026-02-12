#!/bin/bash
# Deploy test PostgreSQL cluster
# Run this AFTER deploying the operator with build.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
COMPONENT_DIR="$PROJECT_ROOT/components/postgres"
HELM_DIR="$COMPONENT_DIR/helm"

source "$PROJECT_ROOT/scripts/common/utils.sh"
source "$PROJECT_ROOT/scripts/common/config-loader.sh"

# Check if operator is deployed
if ! kubectl get deployment -n "$POSTGRES_NAMESPACE" -l app.kubernetes.io/name=cloudnative-pg &>/dev/null; then
    print_error "CloudNativePG operator not found"
    print_info "Deploy operator first: ./components/postgres/scripts/build.sh"
    exit 1
fi

print_info "Deploying test PostgreSQL cluster..."
echo "=========================================="

# Deploy test cluster
kubectl apply -f "$HELM_DIR/manifests/test-cluster.yaml" -n "$POSTGRES_NAMESPACE"

# Wait for cluster ready (takes 1-2 minutes)
print_info "Waiting for PostgreSQL cluster to be ready (this takes 1-2 minutes)..."
for i in {1..36}; do
    PHASE=$(kubectl get cluster test-cluster -n "$POSTGRES_NAMESPACE" \
        -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
    
    if [[ "$PHASE" == "Cluster in healthy state" ]]; then
        break
    fi
    
    if [[ "$i" -eq 36 ]]; then
        print_error "PostgreSQL cluster not ready after 3 minutes"
        print_info "Check status: kubectl get cluster test-cluster -n $POSTGRES_NAMESPACE"
        print_info "Check pods: kubectl get pods -n $POSTGRES_NAMESPACE"
        print_info "Check events: kubectl get events -n $POSTGRES_NAMESPACE --sort-by='.lastTimestamp'"
        exit 1
    fi
    
    sleep 5
done

print_success "Test PostgreSQL cluster deployed!"
echo "=========================================="
echo ""
print_info "Cluster Status:"
kubectl -n "$POSTGRES_NAMESPACE" get cluster test-cluster
echo ""
print_info "PostgreSQL Pods:"
kubectl -n "$POSTGRES_NAMESPACE" get pods -l cnpg.io/cluster=test-cluster
echo ""
print_info "Connection Info:"
echo "  Service: test-cluster-rw.${POSTGRES_NAMESPACE}.svc.cluster.local:5432"
echo "  Database: app"
echo "  User: app"
echo "  Password: kubectl get secret test-cluster-app -n ${POSTGRES_NAMESPACE} -o jsonpath='{.data.password}' | base64 -d"
echo ""
print_info "Test connection:"
echo "  kubectl exec -it -n ${POSTGRES_NAMESPACE} test-cluster-1 -- psql -U app"
echo ""
print_info "Cleanup:"
echo "  kubectl delete cluster test-cluster -n ${POSTGRES_NAMESPACE}"
