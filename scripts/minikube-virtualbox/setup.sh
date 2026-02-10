#!/bin/bash
# Minikube setup script for WSL + VirtualBox driver
# Run this from WSL (not inside Vagrant VM)
# Prerequisites: VirtualBox installed on Windows, minikube installed in WSL

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

print_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }

# Configuration
CLUSTER_NAME="ceph-cluster"
NODES=3
CPUS_PER_NODE=7
MEMORY_PER_NODE=12288  # 12GB per node
DISK_SIZE="40g"
K8S_VERSION="v1.31.0"

print_info "=== Minikube + VirtualBox Setup for Ceph ==="
print_info "Configuration:"
print_info "  Driver: VirtualBox"
print_info "  Nodes: $NODES"
print_info "  CPUs per node: $CPUS_PER_NODE"
print_info "  Memory per node: ${MEMORY_PER_NODE}MB"
print_info "  Disk per node: $DISK_SIZE"
print_info "  Kubernetes: $K8S_VERSION"
echo ""

# Check prerequisites
print_info "Checking prerequisites..."

# Check if running in WSL
if ! grep -qi microsoft /proc/version; then
    print_error "This script must be run from WSL"
    exit 1
fi
print_success "✓ Running in WSL"

# Check if VBoxManage.exe is accessible
if ! command -v VBoxManage.exe &> /dev/null; then
    print_error "VBoxManage.exe not found. Make sure VirtualBox is installed on Windows"
    print_info "Add VirtualBox to Windows PATH or create symlink:"
    print_info "  ln -s '/mnt/c/Program Files/Oracle/VirtualBox/VBoxManage.exe' /usr/local/bin/VBoxManage.exe"
    exit 1
fi
print_success "✓ VirtualBox found"

# Check if minikube is installed
if ! command -v minikube &> /dev/null; then
    print_warning "minikube not found. Installing..."
    curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
    sudo install minikube-linux-amd64 /usr/local/bin/minikube
    rm minikube-linux-amd64
    print_success "✓ minikube installed"
else
    print_success "✓ minikube found ($(minikube version --short))"
fi

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
    print_warning "kubectl not found. Installing..."
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    rm kubectl
    print_success "✓ kubectl installed"
else
    print_success "✓ kubectl found"
fi

echo ""
print_info "Starting minikube cluster..."

# Start minikube with VirtualBox driver
minikube start \
    --driver=virtualbox \
    --nodes=$NODES \
    --cpus=$CPUS_PER_NODE \
    --memory=$MEMORY_PER_NODE \
    --disk-size=$DISK_SIZE \
    --kubernetes-version=$K8S_VERSION \
    --extra-config=kubelet.housekeeping-interval=10s \
    --extra-config=kubelet.max-pods=50 \
    --extra-config=kubelet.serialize-image-pulls=false \
    --extra-config=kubelet.max-parallel-image-pulls=10 \
    --extra-config=kubelet.registry-pull-qps=10 \
    --extra-config=kubelet.registry-burst=20

print_success "Minikube cluster started!"

# Wait for nodes to be ready
print_info "Waiting for nodes to be ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=300s

# Enable addons
print_info "Enabling addons..."
minikube addons enable ingress
minikube addons enable ingress-dns
minikube addons enable dashboard
minikube addons enable metrics-server
minikube addons enable metallb

# Configure MetalLB
print_info "Configuring MetalLB..."
MINIKUBE_IP=$(minikube ip)
SUBNET=$(echo "$MINIKUBE_IP" | cut -d. -f1-3)

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

print_success "MetalLB configured with range: ${SUBNET}.200-${SUBNET}.250"

# Label nodes for Ceph
print_info "Labeling nodes for Ceph storage..."
for node in $(kubectl get nodes -o jsonpath='{.items[*].metadata.name}'); do
    kubectl label node "$node" ceph-osd=enabled ceph-mon=enabled ceph-rgw=enabled --overwrite
done

# Add extra disks for Ceph (optional but recommended)
print_info "Adding extra disks for Ceph OSDs..."
for i in $(seq 1 $NODES); do
    node_name="$CLUSTER_NAME"
    if [ $i -gt 1 ]; then
        node_name="$CLUSTER_NAME-m0$((i-1))"
    fi
    
    disk_file="$HOME/.minikube/machines/$node_name/ceph-disk.vdi"
    
    # Create 20GB disk if it doesn't exist
    if [ ! -f "$disk_file" ]; then
        print_info "  Creating disk for node: $node_name"
        VBoxManage.exe createhd --filename "$(wslpath -w "$disk_file")" --size 20480 --format VDI
        VBoxManage.exe storageattach "$node_name" --storagectl "SATA" --port 1 --device 0 --type hdd --medium "$(wslpath -w "$disk_file")"
    fi
done

print_success "Extra disks added for Ceph"

echo ""
print_success "=== Cluster Ready! ==="
echo ""
print_info "Cluster information:"
kubectl cluster-info
echo ""
print_info "Nodes:"
kubectl get nodes -o wide
echo ""
print_info "Next steps:"
print_info "  1. Deploy Ceph: cd $PROJECT_ROOT && ./components/ceph/scripts/build.sh"
print_info "  2. Access dashboard: minikube dashboard"
print_info "  3. Check cluster: kubectl get nodes"
echo ""
print_info "Useful commands:"
print_info "  minikube status       - Check cluster status"
print_info "  minikube stop         - Stop cluster (preserves state)"
print_info "  minikube delete       - Delete cluster"
print_info "  minikube ssh          - SSH into control plane node"
print_info "  minikube ssh -n <node> - SSH into specific node"
