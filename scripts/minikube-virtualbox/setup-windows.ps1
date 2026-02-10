# Minikube setup for Windows with VirtualBox driver
# Run this from PowerShell (as Administrator)

$ErrorActionPreference = "Stop"

# Configuration
$MINIKUBE_DIR = "C:\Work\mini-vbox"
$NODES = 3
$CPUS_PER_NODE = 7
$MEMORY_PER_NODE = 12288
$DISK_SIZE = "40g"
$K8S_VERSION = "v1.31.0"

Write-Host "[INFO] === Minikube + VirtualBox Setup for Windows ===" -ForegroundColor Green
Write-Host "[INFO] Configuration:" -ForegroundColor Green
Write-Host "  Driver: VirtualBox"
Write-Host "  Nodes: $NODES"
Write-Host "  CPUs per node: $CPUS_PER_NODE"
Write-Host "  Memory per node: ${MEMORY_PER_NODE}MB"
Write-Host "  Disk per node: $DISK_SIZE"
Write-Host "  Kubernetes: $K8S_VERSION"
Write-Host "  Install directory: $MINIKUBE_DIR"
Write-Host ""

# Create bin directory
if (-not (Test-Path $MINIKUBE_DIR)) {
    New-Item -Path $MINIKUBE_DIR -ItemType Directory -Force | Out-Null
    Write-Host "[SUCCESS] Created $MINIKUBE_DIR" -ForegroundColor Green
}

# Download minikube if not exists
$MINIKUBE_EXE = Join-Path $MINIKUBE_DIR "minikube.exe"
if (-not (Test-Path $MINIKUBE_EXE)) {
    Write-Host "[INFO] Downloading minikube..." -ForegroundColor Yellow
    Invoke-WebRequest -OutFile $MINIKUBE_EXE -Uri 'https://github.com/kubernetes/minikube/releases/latest/download/minikube-windows-amd64.exe' -UseBasicParsing
    Write-Host "[SUCCESS] Downloaded minikube" -ForegroundColor Green
} else {
    Write-Host "[SUCCESS] minikube already installed" -ForegroundColor Green
}

# Download kubectl if not exists
$KUBECTL_EXE = Join-Path $MINIKUBE_DIR "kubectl.exe"
if (-not (Test-Path $KUBECTL_EXE)) {
    Write-Host "[INFO] Downloading kubectl..." -ForegroundColor Yellow
    Invoke-WebRequest -OutFile $KUBECTL_EXE -Uri "https://dl.k8s.io/release/$K8S_VERSION/bin/windows/amd64/kubectl.exe" -UseBasicParsing
    Write-Host "[SUCCESS] Downloaded kubectl" -ForegroundColor Green
} else {
    Write-Host "[SUCCESS] kubectl already installed" -ForegroundColor Green
}

# Check VirtualBox
$vboxManage = Get-Command VBoxManage.exe -ErrorAction SilentlyContinue
if (-not $vboxManage) {
    Write-Host "[ERROR] VirtualBox not found. Please install VirtualBox first." -ForegroundColor Red
    exit 1
}
Write-Host "[SUCCESS] VirtualBox found" -ForegroundColor Green

Write-Host ""
Write-Host "[INFO] Starting minikube cluster..." -ForegroundColor Yellow

# Start minikube
& $MINIKUBE_EXE start `
    --driver=virtualbox `
    --nodes=$NODES `
    --cpus=$CPUS_PER_NODE `
    --memory=$MEMORY_PER_NODE `
    --disk-size=$DISK_SIZE `
    --kubernetes-version=$K8S_VERSION `
    --extra-config=kubelet.housekeeping-interval=10s `
    --extra-config=kubelet.max-pods=50 `
    --extra-config=kubelet.fail-swap-on=false

if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Minikube failed to start" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "[SUCCESS] Minikube cluster started!" -ForegroundColor Green

# Wait for nodes
Write-Host "[INFO] Waiting for nodes to be ready..." -ForegroundColor Yellow
& $KUBECTL_EXE wait --for=condition=Ready nodes --all --timeout=300s

# Enable addons
Write-Host "[INFO] Enabling addons..." -ForegroundColor Yellow
& $MINIKUBE_EXE addons enable ingress
& $MINIKUBE_EXE addons enable dashboard
& $MINIKUBE_EXE addons enable metrics-server
& $MINIKUBE_EXE addons enable metallb

Write-Host ""
Write-Host "[SUCCESS] === Cluster Ready! ===" -ForegroundColor Green
Write-Host ""
Write-Host "[INFO] Cluster information:" -ForegroundColor Cyan
& $KUBECTL_EXE cluster-info
Write-Host ""
Write-Host "[INFO] Nodes:" -ForegroundColor Cyan
& $KUBECTL_EXE get nodes -o wide
Write-Host ""
Write-Host "[INFO] Next steps:" -ForegroundColor Cyan
Write-Host "  1. Deploy Ceph from WSL"
Write-Host "  2. Access dashboard: .\bin\minikube.exe dashboard"
Write-Host "  3. Check cluster: .\bin\kubectl.exe get nodes"
Write-Host ""
Write-Host "[INFO] To use kubectl from WSL:" -ForegroundColor Cyan
Write-Host "  cp /mnt/c/Users/$env:USERNAME/.kube/config ~/.kube/config"
