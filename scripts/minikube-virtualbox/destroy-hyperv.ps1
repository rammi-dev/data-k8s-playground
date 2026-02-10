# Complete removal of Minikube Hyper-V setup
# Run this from PowerShell (as Administrator)
# This removes: cluster, VMs, virtual switch, installation directory, and minikube data

$ErrorActionPreference = "Continue"

$MINIKUBE_DIR = "C:\Work\mini-vbox"
$MINIKUBE_EXE = Join-Path $MINIKUBE_DIR "minikube.exe"
$SWITCH_NAME = "minikube-external"

Write-Host ""
Write-Host "============================================" -ForegroundColor Red
Write-Host "  COMPLETE MINIKUBE HYPER-V REMOVAL" -ForegroundColor Red
Write-Host "============================================" -ForegroundColor Red
Write-Host ""
Write-Host "This will remove:" -ForegroundColor Yellow
Write-Host "  - Minikube cluster and all VMs"
Write-Host "  - Virtual switch: $SWITCH_NAME"
Write-Host "  - Minikube data: $env:USERPROFILE\.minikube"
Write-Host "  - Minikube kubeconfig context"
Write-Host ""
Write-Host "Preserved (not removed):" -ForegroundColor Cyan
Write-Host "  - $MINIKUBE_DIR\minikube.exe"
Write-Host "  - $MINIKUBE_DIR\kubectl.exe"
Write-Host ""

$confirm = Read-Host "Are you sure you want to proceed? (yes/no)"
if ($confirm -ne "yes") {
    Write-Host "[INFO] Aborted." -ForegroundColor Cyan
    exit 0
}

Write-Host ""

# Step 1: Delete minikube cluster
Write-Host "[INFO] Step 1: Deleting minikube cluster..." -ForegroundColor Yellow
if (Test-Path $MINIKUBE_EXE) {
    & $MINIKUBE_EXE delete --all --purge 2>$null
    Write-Host "[SUCCESS] Minikube cluster deleted" -ForegroundColor Green
} else {
    Write-Host "[SKIP] Minikube executable not found" -ForegroundColor Gray
}

# Step 2: Stop and remove any remaining Hyper-V VMs with "minikube" in name
Write-Host "[INFO] Step 2: Removing any remaining minikube VMs..." -ForegroundColor Yellow
$minikubeVMs = Get-VM | Where-Object { $_.Name -like "*minikube*" }
foreach ($vm in $minikubeVMs) {
    Write-Host "  Removing VM: $($vm.Name)"
    if ($vm.State -ne "Off") {
        Stop-VM -Name $vm.Name -Force -TurnOff 2>$null
    }
    Remove-VM -Name $vm.Name -Force 2>$null
}
if ($minikubeVMs.Count -eq 0) {
    Write-Host "[SKIP] No minikube VMs found" -ForegroundColor Gray
} else {
    Write-Host "[SUCCESS] Removed $($minikubeVMs.Count) VM(s)" -ForegroundColor Green
}

# Step 3: Remove virtual switch
Write-Host "[INFO] Step 3: Removing virtual switch..." -ForegroundColor Yellow
$switch = Get-VMSwitch -Name $SWITCH_NAME -ErrorAction SilentlyContinue
if ($switch) {
    Remove-VMSwitch -Name $SWITCH_NAME -Force 2>$null
    Write-Host "[SUCCESS] Removed virtual switch: $SWITCH_NAME" -ForegroundColor Green
} else {
    Write-Host "[SKIP] Virtual switch not found" -ForegroundColor Gray
}

# Step 4: Remove minikube data directory
Write-Host "[INFO] Step 4: Removing minikube data directory..." -ForegroundColor Yellow
$minikubeDataDir = Join-Path $env:USERPROFILE ".minikube"
if (Test-Path $minikubeDataDir) {
    # Remove VHDx files first (they can be locked)
    Get-ChildItem $minikubeDataDir -Recurse -Filter "*.vhdx" -ErrorAction SilentlyContinue | ForEach-Object {
        Write-Host "  Removing: $($_.FullName)"
        Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
    }
    # Remove the directory
    Remove-Item $minikubeDataDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "[SUCCESS] Removed minikube data directory" -ForegroundColor Green
} else {
    Write-Host "[SKIP] Minikube data directory not found" -ForegroundColor Gray
}

# Step 5: Clean installation directory (preserve minikube.exe and kubectl.exe)
Write-Host "[INFO] Step 5: Cleaning installation directory (keeping binaries)..." -ForegroundColor Yellow
if (Test-Path $MINIKUBE_DIR) {
    # Remove everything except minikube.exe and kubectl.exe
    Get-ChildItem $MINIKUBE_DIR -Exclude "minikube.exe","kubectl.exe" -ErrorAction SilentlyContinue | ForEach-Object {
        Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }
    Write-Host "[SUCCESS] Cleaned installation directory (binaries preserved)" -ForegroundColor Green
} else {
    Write-Host "[SKIP] Installation directory not found" -ForegroundColor Gray
}

# Step 6: Clean up kubeconfig
Write-Host "[INFO] Step 6: Cleaning up kubeconfig..." -ForegroundColor Yellow
$kubeconfig = Join-Path $env:USERPROFILE ".kube\config"
if (Test-Path $kubeconfig) {
    # Use kubectl to remove minikube context if kubectl exists in PATH
    $kubectl = Get-Command kubectl -ErrorAction SilentlyContinue
    if ($kubectl) {
        kubectl config unset users.minikube 2>$null
        kubectl config unset contexts.minikube 2>$null
        kubectl config unset clusters.minikube 2>$null
        Write-Host "[SUCCESS] Removed minikube from kubeconfig" -ForegroundColor Green
    } else {
        Write-Host "[INFO] kubectl not in PATH, kubeconfig not modified" -ForegroundColor Gray
        Write-Host "  Manually remove minikube entries from: $kubeconfig"
    }
} else {
    Write-Host "[SKIP] Kubeconfig not found" -ForegroundColor Gray
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "  REMOVAL COMPLETE" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""
Write-Host "[INFO] Everything has been removed. You can now run:" -ForegroundColor Cyan
Write-Host "  .\setup-hyperv.ps1" -ForegroundColor White
Write-Host ""
Write-Host "[INFO] If WSL kubeconfig needs cleanup, run in WSL:" -ForegroundColor Cyan
Write-Host "  rm -f ~/.kube/config" -ForegroundColor White
Write-Host ""
