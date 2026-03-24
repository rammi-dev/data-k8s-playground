# Minikube setup for Windows with Hyper-V driver
# Run this from PowerShell (as Administrator)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\common.ps1"

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

# Download or update minikube
$MINIKUBE_EXE = Join-Path $MINIKUBE_DIR "minikube.exe"
$shouldDownload = -not (Test-Path $MINIKUBE_EXE)

if (Test-Path $MINIKUBE_EXE) {
    try {
        $currentVersion = (& $MINIKUBE_EXE version --short 2>$null).Trim()
        if ($currentVersion) {
            $latestRelease = Invoke-RestMethod -Uri "https://api.github.com/repos/kubernetes/minikube/releases/latest"
            $latestVersion = $latestRelease.tag_name
            
            if ($currentVersion -ne $latestVersion) {
                Write-Host "[INFO] Update available: $currentVersion -> $latestVersion" -ForegroundColor Cyan
                $shouldDownload = $true
            } else {
                Write-Host "[SUCCESS] minikube is up to date ($currentVersion)" -ForegroundColor Green
            }
        } else {
            $shouldDownload = $true
        }
    } catch {
        Write-Host "[WARNING] Could not check for updates. Using existing minikube." -ForegroundColor Yellow
    }
}

if ($shouldDownload) {
    Write-Host "[INFO] Downloading latest minikube..." -ForegroundColor Yellow
    # Ensure no processes are locking the file
    Get-Process minikube -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
    
    Invoke-WebRequest -OutFile $MINIKUBE_EXE -Uri 'https://github.com/kubernetes/minikube/releases/latest/download/minikube-windows-amd64.exe' -UseBasicParsing
    Write-Host "[SUCCESS] Downloaded minikube" -ForegroundColor Green
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
$existingSwitch = Get-VMSwitch -Name $switchName -ErrorAction Ignore
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
        Write-Host "[INFO] Removing broken virtual switch: $switchName..." -ForegroundColor Yellow
        Remove-VMSwitch -Name $switchName -Force
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
Write-Host "[INFO] Ensuring 'minikube' profile is clean..." -ForegroundColor Yellow

# Aggressively stop and REMOVE any VMs that might be locking the files
Write-Host "  Checking for Minikube VMs in Hyper-V..."
Get-VM | Where-Object { $_.Name -like "minikube*" } | ForEach-Object {
    Write-Host "  Identified VM: $($_.Name) (State: $($_.State))..." -ForegroundColor Cyan
    if ($_.State -ne "Off") {
        Write-Host "    Stopping VM..."
        Stop-VM -Name $_.Name -Force -TurnOff
    }
    Write-Host "    Removing VM from Hyper-V..."
    Remove-VM -Name $_.Name -Force
}

# Run delete to clear any half-removed or corrupt state for the targeted profile
try {
    & $MINIKUBE_EXE delete -p minikube
} catch {
    Write-Host "[WARNING] 'minikube delete' reported an error, attempting manual cleanup..." -ForegroundColor Yellow
}

# Also manually clear the machine folders if they still exist (surgical)
@("minikube", "minikube-m02", "minikube-m03") | ForEach-Object {
    $path = Join-Path $env:USERPROFILE ".minikube\machines\$_"
    if (Test-Path $path) {
        Write-Host "  Removing machine folder: $_"
        try {
            Remove-Item $path -Recurse -Force -ErrorAction Stop
        } catch {
            Write-Host "[ERROR] Could not remove $path. The file is still locked by another process." -ForegroundColor Red
            Write-Host "        Please close Hyper-V Manager and any other programs using this VM." -ForegroundColor Yellow
            Write-Host "        If it still fails, you may need to restart your computer." -ForegroundColor Yellow
            throw $_
        }
    }
}

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

# Fix image pulls — Hyper-V VMs have no IPv6 routing, but DNS returns AAAA records.
# Go/Docker tries IPv6 first and fails. Fix: inject /etc/hosts with IPv4-only addresses.
Write-Host ""
Write-Host "[INFO] Fixing container registry access on all nodes (IPv4 /etc/hosts)..." -ForegroundColor Yellow
$vmNames = Get-AllNodeNames
Fix-RegistryAccess -NodeNames $vmNames

# Attach extra VHDs for Ceph OSD (--extra-disks not supported on Hyper-V driver)
# VMs must be stopped to attach new disks, then restarted
Write-Host ""
Write-Host "[INFO] Attaching extra disks for Ceph OSD..." -ForegroundColor Yellow

# Check if any VMs need disks attached
$needsAttach = $false
foreach ($vmName in $vmNames) {
    if (-not (Get-VM -Name $vmName -ErrorAction Ignore)) { continue }
    $vm = Get-VM -Name $vmName
    $vhdPath = Join-Path (Split-Path $vm.HardDrives[0].Path) "ceph-osd.vhdx"
    $existingDisk = $vm.HardDrives | Where-Object { $_.Path -eq $vhdPath }
    if (-not $existingDisk) { $needsAttach = $true; break }
}

if ($needsAttach) {
    # Stop all VMs to attach disks
    Write-Host "[INFO] Stopping VMs... " -ForegroundColor Yellow
    foreach ($vmName in $vmNames) {
        if (Get-VM -Name $vmName -ErrorAction Ignore) {
            Write-Host "  Stopping $vmName..."
            Stop-VM -Name $vmName -Force
        }
    }
    # Wait for all VMs to stop
    foreach ($vmName in $vmNames) {
        if (Get-VM -Name $vmName -ErrorAction Ignore) {
            while ((Get-VM -Name $vmName).State -ne "Off") {
                Start-Sleep -Seconds 2
            }
        }
    }

    foreach ($vmName in $vmNames) {
        $vm = Get-VM -Name $vmName -ErrorAction Ignore
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

        # Attach to stopped VM
        Add-VMHardDiskDrive -VMName $vmName -Path $vhdPath
        Write-Host "[SUCCESS] Attached extra disk to $vmName" -ForegroundColor Green
    }

    # Restart VMs via minikube start (restores kubelet, apiserver, docker properly)
    Write-Host "[INFO] Restarting cluster via minikube start..." -ForegroundColor Yellow
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
        Write-Host "[ERROR] Minikube failed to restart after disk attachment" -ForegroundColor Red
        exit 1
    }
    Write-Host "[SUCCESS] Cluster restarted with extra disks" -ForegroundColor Green

    # Re-apply /etc/hosts after restart (root fs is tmpfs, lost on reboot)
    Write-Host "[INFO] Re-applying registry /etc/hosts fix after restart..." -ForegroundColor Yellow
    Fix-RegistryAccess -NodeNames $vmNames
} else {
    Write-Host "[SUCCESS] Extra disks already attached to all nodes" -ForegroundColor Green
}

Write-Host "[SUCCESS] Extra disks ready on all nodes" -ForegroundColor Green

# Wait for all nodes to be Ready
Write-Host "[INFO] Waiting for nodes to be ready..." -ForegroundColor Yellow
& $KUBECTL_EXE wait --for=condition=Ready nodes --all --timeout=300s

# Enable addons
# Note: ingress/ingress-dns removed — Envoy Gateway / Istio handle Gateway API ingress
Write-Host "[INFO] Enabling addons..." -ForegroundColor Yellow
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
