#!/bin/bash
# Access Dremio UI via port-forward
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$PROJECT_ROOT/scripts/common/utils.sh"
source "$PROJECT_ROOT/scripts/common/config-loader.sh"

UI_PORT=9047
CLIENT_PORT=31010
FLIGHT_PORT=32010

print_info "=== Dremio UI ==="
echo "  URL:    http://localhost:$UI_PORT"
echo ""
echo "  First-time setup:"
echo "    1. Create admin username and password"
echo "    2. Go to Settings -> Engines -> Add Engine"
echo "    3. Size: Small (1 pod, 10Gi) | CPU: 1C | Offset: reserve-0-0"
echo ""
print_info "=== Dremio Connections ==="
echo "  ODBC/JDBC: localhost:$CLIENT_PORT"
echo "  Arrow Flight: localhost:$FLIGHT_PORT"
echo ""

print_info "Starting port-forwards (Ctrl+C to stop)..."
kubectl -n "$DREMIO_NAMESPACE" port-forward svc/dremio-client "$UI_PORT:9047" &
kubectl -n "$DREMIO_NAMESPACE" port-forward svc/dremio-client "$CLIENT_PORT:31010" &
kubectl -n "$DREMIO_NAMESPACE" port-forward svc/dremio-client "$FLIGHT_PORT:32010" &
wait
