#!/bin/bash
# Access Kubernetes Dashboard
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common/utils.sh"

print_info "Starting Kubernetes Dashboard..."
print_info "This will open the dashboard in your browser"
echo ""

minikube dashboard
