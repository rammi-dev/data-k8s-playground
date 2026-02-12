#!/bin/bash
# Port-forward Airflow Webserver for local access
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

LOCAL_PORT=8080

print_info "Airflow Webserver Access"
echo "=========================================="

# Check if Airflow is deployed
if ! kubectl get svc -n "${AIRFLOW_NAMESPACE}" -l component=webserver &>/dev/null 2>&1; then
    print_error "Airflow webserver service not found in namespace ${AIRFLOW_NAMESPACE}"
    print_info "Deploy Airflow first: ./components/airflow/scripts/build.sh"
    exit 1
fi

WEBSERVER_SVC=$(kubectl get svc -n "${AIRFLOW_NAMESPACE}" -l component=webserver -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [[ -z "$WEBSERVER_SVC" ]]; then
    print_error "Could not find Airflow webserver service"
    exit 1
fi

echo ""
print_info "Airflow Webserver URL: http://localhost:${LOCAL_PORT}"
echo ""
print_info "Starting port-forward (Ctrl+C to stop)..."
kubectl port-forward svc/${WEBSERVER_SVC} ${LOCAL_PORT}:8080 -n "${AIRFLOW_NAMESPACE}"
