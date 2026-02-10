#!/bin/bash
# Fix kubeconfig for WSL access to Windows minikube
# Run this from WSL after minikube is started on Windows

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

print_info() { echo -e "${CYAN}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

print_info "=== Configuring kubectl for WSL ==="
echo ""

# Detect Windows username
WIN_USER=$(cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r')

if [ -z "$WIN_USER" ]; then
    print_warning "Could not detect Windows username"
    read -p "Enter your Windows username: " WIN_USER
fi

print_info "Windows username: $WIN_USER"

# Paths
WIN_KUBECONFIG="/mnt/c/Users/$WIN_USER/.kube/config"
WSL_KUBECONFIG="$HOME/.kube/config"

# Check if Windows kubeconfig exists
if [ ! -f "$WIN_KUBECONFIG" ]; then
    echo ""
    print_warning "Windows kubeconfig not found at: $WIN_KUBECONFIG"
    print_info "Make sure minikube is running on Windows first:"
    print_info "  C:\\Work\\mini-vbox\\minikube.exe status"
    exit 1
fi

print_success "Found Windows kubeconfig"

# Create .kube directory
mkdir -p ~/.kube

# Backup existing config
if [ -f "$WSL_KUBECONFIG" ]; then
    print_info "Backing up existing kubeconfig to ~/.kube/config.backup"
    cp "$WSL_KUBECONFIG" "$WSL_KUBECONFIG.backup"
fi

# Copy kubeconfig
print_info "Copying kubeconfig from Windows..."
cp "$WIN_KUBECONFIG" "$WSL_KUBECONFIG"

# Fix Windows paths to WSL paths
print_info "Converting Windows paths to WSL paths..."
sed -i "s|C:\\\\Users\\\\$WIN_USER\\\\.minikube|/mnt/c/Users/$WIN_USER/.minikube|g" "$WSL_KUBECONFIG"
sed -i 's|\\|/|g' "$WSL_KUBECONFIG"

print_success "Kubeconfig configured for WSL"

# Test connectivity
echo ""
print_info "Testing kubectl connectivity..."
if kubectl cluster-info &>/dev/null; then
    print_success "kubectl is working!"
    echo ""
    kubectl get nodes
else
    echo ""
    print_warning "kubectl cannot connect to cluster"
    print_info "This might be a networking issue. Check if:"
    print_info "  1. Minikube is running: C:\\Work\\mini-vbox\\minikube.exe status"
    print_info "  2. External switch is configured: Get-VMSwitch -Name minikube-external"
    print_info "  3. WSL can ping the cluster IP"
fi

echo ""
print_info "Kubeconfig location: $WSL_KUBECONFIG"
print_info "You can now use kubectl from WSL!"
