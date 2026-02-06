#!/bin/bash
# Access Kubernetes Dashboard from Windows host
# Run this script inside the Vagrant VM
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common/utils.sh"
source "$SCRIPT_DIR/../common/config-loader.sh"

# Fixed port for consistent access
PROXY_PORT=30080

print_info "Starting Kubernetes Dashboard..."
print_info "Dashboard will be accessible from Windows browser"
echo ""

# Check if proxy is already running
if pgrep -f "kubectl proxy.*$PROXY_PORT" > /dev/null; then
    print_warning "Dashboard proxy is already running on port $PROXY_PORT"
else
    # Start kubectl proxy in background, binding to all interfaces
    print_info "Starting kubectl proxy on port $PROXY_PORT..."
    nohup kubectl proxy --address='0.0.0.0' --port=$PROXY_PORT --accept-hosts='.*' > /tmp/dashboard-proxy.log 2>&1 &
    sleep 2
    
    if ! pgrep -f "kubectl proxy.*$PROXY_PORT" > /dev/null; then
        print_error "Failed to start proxy. Check /tmp/dashboard-proxy.log"
        exit 1
    fi
fi

# Get VM IP addresses for access
echo ""
print_success "Dashboard is running!"
echo ""
print_info "Access from Windows browser using one of these URLs:"
echo ""

# NAT port forward (if configured in Vagrantfile)
echo "  Via NAT (localhost):"
echo "  http://localhost:$PROXY_PORT/api/v1/namespaces/kubernetes-dashboard/services/http:kubernetes-dashboard:/proxy/"
echo ""

# Bridged network IP
BRIDGED_IP=$(ip -4 addr show | grep -oP '192\.168\.\d+\.\d+' | head -1)
if [[ -n "$BRIDGED_IP" ]]; then
    echo "  Via Bridged Network:"
    echo "  http://${BRIDGED_IP}:${PROXY_PORT}/api/v1/namespaces/kubernetes-dashboard/services/http:kubernetes-dashboard:/proxy/"
    echo ""
fi

# Host-only network IP
HOSTONLY_IP=$(ip -4 addr show | grep -oP '192\.168\.56\.\d+' | head -1)
if [[ -n "$HOSTONLY_IP" ]]; then
    echo "  Via Host-Only Network:"
    echo "  http://${HOSTONLY_IP}:${PROXY_PORT}/api/v1/namespaces/kubernetes-dashboard/services/http:kubernetes-dashboard:/proxy/"
    echo ""
fi

print_info "To stop the dashboard proxy: pkill -f 'kubectl proxy'"
