#!/bin/bash
# Access Grafana UI via port-forward
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../scripts/common/utils.sh"

NAMESPACE="monitoring"
RELEASE_NAME="loki"
LOCAL_PORT=3000

print_info "Accessing Grafana"
echo "=========================================="

# Get Grafana admin password
GRAFANA_PASSWORD=$(kubectl get secret --namespace ${NAMESPACE} ${RELEASE_NAME}-grafana -o jsonpath="{.data.admin-password}" | base64 --decode)

echo ""
print_info "Grafana Credentials:"
echo "  URL: http://localhost:${LOCAL_PORT}"
echo "  Username: admin"
echo "  Password: ${GRAFANA_PASSWORD}"
echo ""
echo "=========================================="
print_info "Port-forwarding Grafana..."
echo "Press Ctrl+C to stop"
echo "=========================================="

# Port-forward Grafana service
kubectl port-forward --namespace ${NAMESPACE} service/${RELEASE_NAME}-grafana ${LOCAL_PORT}:80
