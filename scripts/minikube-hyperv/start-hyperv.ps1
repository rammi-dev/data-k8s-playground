# Start minikube cluster and re-apply registry fix
# Use this instead of bare "minikube start" — root fs is tmpfs, /etc/hosts is lost on every reboot
# Run from PowerShell (as Administrator)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\common.ps1"

Write-Host "[INFO] Starting minikube cluster..." -ForegroundColor Yellow
& $MINIKUBE_EXE start `
    --driver=hyperv `
    --hyperv-virtual-switch=minikube-external `
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

# Wait for nodes
Write-Host "[INFO] Waiting for nodes to be ready..." -ForegroundColor Yellow
& $KUBECTL_EXE wait --for=condition=Ready nodes --all --timeout=300s

# Re-apply /etc/hosts fix (lost on reboot since root fs is tmpfs)
Write-Host ""
Write-Host "[INFO] Applying registry /etc/hosts fix (IPv4-only)..." -ForegroundColor Yellow
$nodeNames = Get-AllNodeNames
Fix-RegistryAccess -NodeNames $nodeNames

Write-Host ""
Write-Host "[SUCCESS] Cluster is ready!" -ForegroundColor Green
& $KUBECTL_EXE get nodes -o wide
