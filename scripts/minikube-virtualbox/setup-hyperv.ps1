# Minikube setup for Windows with Hyper-V driver
# Run this from PowerShell (as Administrator)

$ErrorActionPreference = "Stop"

# Configuration
$MINIKUBE_DIR = "C:\Work\mini-vbox"
$NODES = 3
$CPUS_PER_NODE = 7
$MEMORY_PER_NODE = 12288
$DISK_SIZE = "40g"
$EXTRA_DISK_SIZE = 20GB  # Extra disk per node for Ceph OSD
$K8S_VERSION = "v1.35.0"

Write-Host "[INFO] === Minikube + Hyper-V Setup for Windows ===" -ForegroundColor Green
Write-Host "[INFO] Configuration:" -ForegroundColor Green
Write-Host "  Driver: Hyper-V"
Write-Host "  Nodes: $NODES"
Write-Host "  CPUs per node: $CPUS_PER_NODE"
Write-Host "  Memory per node: ${MEMORY_PER_NODE}MB"
Write-Host "  Disk per node: $DISK_SIZE"
Write-Host "  Extra disk per node: $($EXTRA_DISK_SIZE / 1GB)GB (for Ceph OSD)"
Write-Host "  Kubernetes: $K8S_VERSION"
Write-Host "  Install directory: $MINIKUBE_DIR"
Write-Host "  Virtual Switch: minikube-external"
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

# Check Hyper-V
$hyperv = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All
if ($hyperv.State -ne "Enabled") {
    Write-Host "[ERROR] Hyper-V is not enabled. Please enable it first:" -ForegroundColor Red
    Write-Host "  Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All" -ForegroundColor Yellow
    Write-Host "  Then reboot and run this script again." -ForegroundColor Yellow
    exit 1
}
Write-Host "[SUCCESS] Hyper-V is enabled" -ForegroundColor Green

Write-Host ""
Write-Host "[INFO] Configuring Hyper-V networking for WSL access..." -ForegroundColor Yellow

# Check if external switch exists and is healthy
$switchName = "minikube-external"
$existingSwitch = Get-VMSwitch -Name $switchName -ErrorAction SilentlyContinue
$needsRecreate = $false

if ($existingSwitch) {
    # Check if the switch is connected to an active adapter
    $switchAdapter = $existingSwitch.NetAdapterInterfaceDescription
    if ($switchAdapter) {
        $adapterStatus = Get-NetAdapter | Where-Object { $_.InterfaceDescription -eq $switchAdapter }
        if (-not $adapterStatus -or $adapterStatus.Status -ne "Up") {
            Write-Host "[WARNING] Virtual switch exists but network adapter is not active" -ForegroundColor Yellow
            $needsRecreate = $true
        } else {
            Write-Host "[SUCCESS] External virtual switch exists and is connected to: $($adapterStatus.Name)" -ForegroundColor Green
        }
    } else {
        Write-Host "[WARNING] Virtual switch exists but has no network adapter" -ForegroundColor Yellow
        $needsRecreate = $true
    }
}

if (-not $existingSwitch -or $needsRecreate) {
    # Remove existing broken switch if needed
    if ($needsRecreate -and $existingSwitch) {
        Write-Host "[INFO] Removing broken virtual switch..." -ForegroundColor Yellow
        Remove-VMSwitch -Name $switchName -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }

    Write-Host "[INFO] Creating external virtual switch: $switchName" -ForegroundColor Yellow

    # Find the active physical network adapter, excluding virtual/software adapters
    $activeAdapter = Get-NetAdapter | Where-Object {
        $_.Status -eq "Up" -and
        $_.Name -notlike "vEthernet*" -and
        $_.InterfaceDescription -notlike "VirtualBox*" -and
        $_.InterfaceDescription -notlike "VMware*" -and
        $_.InterfaceDescription -notlike "Hyper-V*" -and
        $_.InterfaceDescription -notlike "*Virtual*" -and
        ($_.Name -like "*Wi-Fi*" -or $_.InterfaceDescription -like "*Wi-Fi*" -or $_.InterfaceDescription -like "*Wireless*")
    } | Select-Object -First 1

    # Fallback: any real physical Ethernet adapter (not virtual)
    if (-not $activeAdapter) {
        $activeAdapter = Get-NetAdapter | Where-Object {
            $_.Status -eq "Up" -and
            $_.Name -notlike "vEthernet*" -and
            $_.InterfaceDescription -notlike "VirtualBox*" -and
            $_.InterfaceDescription -notlike "VMware*" -and
            $_.InterfaceDescription -notlike "Hyper-V*" -and
            $_.InterfaceDescription -notlike "*Virtual*" -and
            $_.InterfaceDescription -notlike "*Loopback*"
        } | Select-Object -First 1
    }

    if (-not $activeAdapter) {
        Write-Host "[ERROR] No active network adapter found" -ForegroundColor Red
        exit 1
    }

    Write-Host "[INFO] Using network adapter: $($activeAdapter.Name)" -ForegroundColor Cyan

    # Create external switch
    New-VMSwitch -Name $switchName -NetAdapterName $activeAdapter.Name -AllowManagementOS $true | Out-Null
    Write-Host "[SUCCESS] Created external virtual switch" -ForegroundColor Green
}

Write-Host ""
Write-Host "[INFO] Starting minikube cluster..." -ForegroundColor Yellow

# Start minikube with Hyper-V driver and external switch
& $MINIKUBE_EXE start `
    --driver=hyperv `
    --hyperv-virtual-switch=$switchName `
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

# Attach extra VHDs for Ceph OSD (--extra-disks not supported on Hyper-V driver)
Write-Host ""
Write-Host "[INFO] Attaching extra disks for Ceph OSD..." -ForegroundColor Yellow

$vmNames = @("minikube")
for ($i = 2; $i -le $NODES; $i++) {
    $vmNames += "minikube-m{0:D2}" -f $i
}

foreach ($vmName in $vmNames) {
    $vm = Get-VM -Name $vmName -ErrorAction SilentlyContinue
    if (-not $vm) {
        Write-Host "[WARNING] VM '$vmName' not found, skipping disk attachment" -ForegroundColor Yellow
        continue
    }

    $vhdPath = Join-Path (Split-Path $vm.HardDrives[0].Path) "ceph-osd.vhdx"

    # Check if disk is already attached
    $existingDisk = $vm.HardDrives | Where-Object { $_.Path -eq $vhdPath }
    if ($existingDisk) {
        Write-Host "[SUCCESS] Extra disk already attached to $vmName" -ForegroundColor Green
        continue
    }

    # Create the VHD if it doesn't exist
    if (-not (Test-Path $vhdPath)) {
        New-VHD -Path $vhdPath -SizeBytes $EXTRA_DISK_SIZE -Dynamic | Out-Null
        Write-Host "[SUCCESS] Created $($EXTRA_DISK_SIZE / 1GB)GB VHD: $vhdPath" -ForegroundColor Green
    }

    # Attach to VM
    Add-VMHardDiskDrive -VMName $vmName -Path $vhdPath
    Write-Host "[SUCCESS] Attached extra disk to $vmName" -ForegroundColor Green
}

Write-Host "[SUCCESS] Extra disks attached to all nodes" -ForegroundColor Green

# Wait for nodes
Write-Host "[INFO] Waiting for nodes to be ready..." -ForegroundColor Yellow
& $KUBECTL_EXE wait --for=condition=Ready nodes --all --timeout=300s

# Enable addons
Write-Host "[INFO] Enabling addons..." -ForegroundColor Yellow
& $MINIKUBE_EXE addons enable ingress
& $MINIKUBE_EXE addons enable ingress-dns
& $MINIKUBE_EXE addons enable dashboard
& $MINIKUBE_EXE addons enable metrics-server
& $MINIKUBE_EXE addons enable registry
& $MINIKUBE_EXE addons enable metallb

# Configure MetalLB with dynamic IP range
Write-Host "[INFO] Configuring MetalLB IP range..." -ForegroundColor Yellow
Start-Sleep -Seconds 5  # Wait for metallb-system namespace

$minikubeIp = & $MINIKUBE_EXE ip
$subnet = ($minikubeIp -split '\.')[0..2] -join '.'
$ipRange = "${subnet}.200-${subnet}.250"

Write-Host "[INFO] MetalLB IP range: $ipRange" -ForegroundColor Cyan

@"
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
      - $ipRange
"@ | & $KUBECTL_EXE apply -f -

Write-Host "[SUCCESS] Addons configured" -ForegroundColor Green

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
Write-Host "  1. Copy kubeconfig to WSL and fix paths:"
Write-Host "     mkdir -p ~/.kube"
Write-Host "     cp /mnt/c/Users/$env:USERNAME/.kube/config ~/.kube/config"
Write-Host "     sed -i 's|C:\\Users\\$env:USERNAME\\.minikube|/mnt/c/Users/$env:USERNAME/.minikube|g' ~/.kube/config"
Write-Host "     sed -i 's|\\|/|g' ~/.kube/config"
Write-Host "  2. Test from WSL: kubectl get nodes"
Write-Host "  3. Deploy Ceph from WSL"
Write-Host "  4. Test image pull speed - should be 20-60x faster!"
Write-Host ""
Write-Host "[INFO] Management commands:" -ForegroundColor Cyan
Write-Host "  C:\Work\mini-vbox\minikube.exe status"
Write-Host "  C:\Work\mini-vbox\minikube.exe stop"
Write-Host "  C:\Work\mini-vbox\minikube.exe delete"
