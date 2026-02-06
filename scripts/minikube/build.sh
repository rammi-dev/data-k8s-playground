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

# Add Docker optimizations if using docker driver
if [[ "$MINIKUBE_DRIVER" == "docker" ]]; then
    MINIKUBE_CMD+=" --docker-opt dns=8.8.8.8 --docker-opt dns=8.8.4.4 --docker-opt mtu=1500"
fi

eval $MINIKUBE_CMD

# Configure Docker inside nodes (Post-Start Workaround)
print_info "Configuring Docker inside minikube nodes (Full Config)..."
# Loop through all nodes (minikube, minikube-m02, etc.)
for ((i=1; i<=$MINIKUBE_NODES; i++)); do
    if [[ $i -eq 1 ]]; then
        NODE_NAME="minikube"
    else
        NODE_NAME="minikube-m0$i"
    fi
    
    print_info "  - Patching $NODE_NAME..."
    # Write optimized daemon.json with ALL settings
    minikube ssh -n "$NODE_NAME" -- sudo tee /etc/docker/daemon.json <<EOF
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {"max-size": "100m"},
  "storage-driver": "overlay2",
  "dns": ["8.8.8.8", "8.8.4.4"],
  "mtu": 1500
}
EOF
    # Restart Docker to apply (run in background to avoid hanging the ssh session)
    minikube ssh -n "$NODE_NAME" -- "sudo nohup sh -c 'sleep 2; systemctl restart docker' >/dev/null 2>&1 &"
done

# Wait for cluster to be ready
print_info "Waiting for cluster to be ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=300s

# Enable addons
print_info "Enabling minikube addons..."

print_info "  - Enabling ingress..."
minikube addons enable ingress

print_info "  - Enabling ingress-dns..."
minikube addons enable ingress-dns

print_info "  - Enabling dashboard..."
minikube addons enable dashboard

print_info "  - Enabling metrics-server..."
minikube addons enable metrics-server

# Local registry for faster multi-node image distribution
print_info "  - Enabling registry..."
minikube addons enable registry

# Note: We skip the following addons because Ceph/Rook provides its own:
# - default-storageclass: Ceph provides rook-ceph-block, rook-cephfs storage classes
# - storage-provisioner: Ceph CSI driver handles provisioning
# - csi-hostpath-driver: Not needed with Ceph
# - volumesnapshots: Ceph provides its own snapshot capability

# MetalLB for LoadBalancer service support
print_info "  - Enabling metallb..."
minikube addons enable metallb

# Configure MetalLB with dynamic IP range based on minikube network
print_info "  - Configuring metallb IP range..."
# Wait for metallb-system namespace to be ready
kubectl wait --for=condition=Ready namespace/metallb-system --timeout=60s 2>/dev/null || sleep 5
MINIKUBE_IP=$(minikube ip)
# Extract the subnet (e.g., 192.168.49.2 -> 192.168.49)
SUBNET=$(echo "$MINIKUBE_IP" | cut -d. -f1-3)
# Use .200-.250 range for LoadBalancer IPs (avoids conflict with node IPs)
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  namespace: metallb-system
  name: config
data:
  config: |
    address-pools:
    - name: default
      protocol: layer2
      addresses:
      - ${SUBNET}.200-${SUBNET}.250
EOF
print_info "  - MetalLB configured with range: ${SUBNET}.200-${SUBNET}.250"

print_success "Minikube cluster is ready!"

# Label nodes for storage (Ceph/Rook placement)
print_info "Labeling nodes for storage placement..."
for node in $(kubectl get nodes -o jsonpath='{.items[*].metadata.name}'); do
    kubectl label node "$node" ceph-osd=enabled ceph-mon=enabled ceph-rgw=enabled --overwrite 2>/dev/null || true
done

# Create directories for Ceph OSD storage on each node (directory-based storage for dev)
print_info "Creating storage directories on nodes..."
for node in $(kubectl get nodes -o jsonpath='{.items[*].metadata.name}'); do
    minikube ssh -n "$node" "sudo mkdir -p /var/lib/rook && sudo chmod 755 /var/lib/rook" 2>/dev/null || true
    # Increase inotify limits for Ceph (prevents watch limit errors)
    minikube ssh -n "$node" "sudo sysctl -w fs.inotify.max_user_watches=1048576" 2>/dev/null || true
    minikube ssh -n "$node" "sudo sysctl -w fs.inotify.max_user_instances=256" 2>/dev/null || true
done

print_info "Cluster info:"
kubectl cluster-info
echo ""
print_info "Nodes:"
kubectl get nodes -o wide
echo ""
print_info "Enabled addons:"
minikube addons list | grep enabled
echo ""
print_info "Storage classes:"
kubectl get storageclass
echo ""
print_info "Next steps:"
print_info "  - Deploy monitoring: ./components/monitoring/scripts/build.sh"
print_info "  - Deploy Ceph storage: ./components/ceph/scripts/build.sh"
print_info "  - Access dashboard: ./scripts/minikube/access-dashboard.sh"
