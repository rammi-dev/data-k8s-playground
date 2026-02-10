#!/bin/bash
# WSL wrapper to call Windows minikube
# This allows you to use minikube from WSL while it runs on Windows

MINIKUBE_EXE="/mnt/c/Work/mini-vbox/minikube.exe"
KUBECTL_EXE="/mnt/c/Work/mini-vbox/kubectl.exe"

# Check if minikube is installed
if [ ! -f "$MINIKUBE_EXE" ]; then
    echo "[ERROR] Minikube not found at $MINIKUBE_EXE"
    echo "[INFO] Please run setup-windows.ps1 from PowerShell first"
    exit 1
fi

# Function to call minikube
minikube() {
    "$MINIKUBE_EXE" "$@"
}

# Function to call kubectl
kubectl() {
    "$KUBECTL_EXE" "$@"
}

# Export functions
export -f minikube kubectl

# Show usage
cat << 'EOF'
[INFO] WSL Wrapper for Windows Minikube

Available commands:
  minikube status       - Check cluster status
  minikube stop         - Stop cluster
  minikube delete       - Delete cluster
  minikube ssh          - SSH into control plane
  kubectl get nodes     - List nodes
  kubectl get pods -A   - List all pods

To use kubectl from WSL permanently:
  mkdir -p ~/.kube
  cp /mnt/c/Users/$USER/.kube/config ~/.kube/config

Then you can use 'kubectl' directly from WSL!
EOF

# Start interactive shell with minikube/kubectl available
bash
