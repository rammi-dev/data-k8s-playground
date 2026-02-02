#!/bin/bash
# Start minikube cluster inside the Vagrant VM
# Run this script from inside the VM: cd /vagrant && ./scripts/minikube/build.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common/utils.sh"
source "$SCRIPT_DIR/../common/config-loader.sh"

# Check if running inside VM
if ! is_vagrant_vm && [[ ! -f /.dockerenv ]]; then
    print_error "This script should be run inside the Vagrant VM"
    print_info "First SSH into the VM: ./scripts/vagrant/ssh.sh"
    exit 1
fi

print_info "Starting minikube cluster"
print_info "Configuration: ${MINIKUBE_NODES} node(s), ${MINIKUBE_CPUS} CPUs, ${MINIKUBE_MEMORY}MB RAM"

# Check if minikube is already running
if minikube status &>/dev/null; then
    print_warning "Minikube is already running"
    minikube status
    exit 0
fi

# Build minikube start command
MINIKUBE_CMD="minikube start"
MINIKUBE_CMD+=" --driver=$MINIKUBE_DRIVER"
MINIKUBE_CMD+=" --nodes=$MINIKUBE_NODES"
MINIKUBE_CMD+=" --cpus=$MINIKUBE_CPUS"
MINIKUBE_CMD+=" --memory=$MINIKUBE_MEMORY"
MINIKUBE_CMD+=" --disk-size=$MINIKUBE_DISK_SIZE"
MINIKUBE_CMD+=" --kubernetes-version=$MINIKUBE_K8S_VERSION"

# Add extra config if defined
if [[ -n "$MINIKUBE_EXTRA_CONFIG" ]]; then
    for cfg in $MINIKUBE_EXTRA_CONFIG; do
        MINIKUBE_CMD+=" --extra-config=$cfg"
    done
fi

# Start minikube
print_info "Running: $MINIKUBE_CMD"
eval $MINIKUBE_CMD

# Wait for cluster to be ready
print_info "Waiting for cluster to be ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=300s

# Enable addons
print_info "Enabling minikube addons..."

print_info "  - Enabling ingress..."
minikube addons enable ingress

print_info "  - Enabling CSI hostpath driver..."
minikube addons enable csi-hostpath-driver

print_info "  - Enabling dashboard..."
minikube addons enable dashboard

print_info "  - Enabling metrics-server..."
minikube addons enable metrics-server

print_success "Minikube cluster is ready!"
print_info "Cluster info:"
kubectl cluster-info
echo ""
print_info "Nodes:"
kubectl get nodes
echo ""
print_info "Enabled addons:"
minikube addons list | grep enabled
