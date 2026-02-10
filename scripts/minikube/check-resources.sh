#!/bin/bash
# Check minikube resources, storage usage, and cluster health
# Works with both Hyper-V (Windows native) and Docker (Vagrant VM) drivers
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common/utils.sh"

# Detect environment
detect_environment() {
    if command -v powershell.exe &>/dev/null; then
        # Running from WSL with access to Windows
        echo "wsl"
    elif [[ -f /vagrant/.vagrant ]]; then
        # Running inside Vagrant VM
        echo "vagrant"
    elif [[ -f /.dockerenv ]]; then
        # Running inside Docker container
        echo "docker"
    else
        echo "linux"
    fi
}

ENV_TYPE=$(detect_environment)

print_header() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  $1"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# ============================================================================
# Minikube Status
# ============================================================================
print_header "MINIKUBE STATUS"

if ! command -v minikube &>/dev/null; then
    print_error "minikube not found in PATH"
    exit 1
fi

DRIVER=$(minikube config get driver 2>/dev/null || echo "unknown")
PROFILE=$(minikube profile list -o json 2>/dev/null | grep -o '"Name":"[^"]*"' | head -1 | cut -d'"' -f4 || echo "minikube")

echo "Profile: $PROFILE"
echo "Driver: $DRIVER"
echo ""

minikube status -p "$PROFILE" 2>/dev/null || print_warning "Minikube may not be running"

# ============================================================================
# Hyper-V VM Resources (Windows/WSL only)
# ============================================================================
if [[ "$ENV_TYPE" == "wsl" ]] && [[ "$DRIVER" == "hyperv" || "$DRIVER" == "unknown" ]]; then
    print_header "HYPER-V VM RESOURCES"

    # Get VM info via PowerShell
    powershell.exe -NoProfile -Command '
        $vms = Get-VM | Where-Object { $_.Name -like "minikube*" }
        if ($vms) {
            $vms | Format-Table Name, State,
                @{N="CPU"; E={$_.ProcessorCount}},
                @{N="CPU%"; E={$_.CPUUsage}},
                @{N="Memory(GB)"; E={[math]::Round($_.MemoryAssigned/1GB, 1)}},
                @{N="Uptime"; E={$_.Uptime}} -AutoSize
        } else {
            Write-Host "No minikube Hyper-V VMs found"
        }
    ' 2>/dev/null || print_warning "Could not query Hyper-V VMs"

    print_header "HYPER-V STORAGE (VHDX FILES)"

    powershell.exe -NoProfile -Command '
        $minikubeDir = "$env:USERPROFILE\.minikube\machines"
        if (Test-Path $minikubeDir) {
            Get-ChildItem $minikubeDir -Recurse -Filter "*.vhdx" -ErrorAction SilentlyContinue |
            ForEach-Object {
                $vhd = Get-VHD $_.FullName -ErrorAction SilentlyContinue
                if ($vhd) {
                    [PSCustomObject]@{
                        Name = $_.Directory.Name
                        "Allocated(GB)" = [math]::Round($vhd.Size/1GB, 1)
                        "Used(GB)" = [math]::Round($vhd.FileSize/1GB, 1)
                        "Free(GB)" = [math]::Round(($vhd.Size - $vhd.FileSize)/1GB, 1)
                        "Usage%" = [math]::Round(($vhd.FileSize/$vhd.Size)*100, 0)
                    }
                }
            } | Format-Table -AutoSize

            # Total storage
            $totalUsed = (Get-ChildItem $minikubeDir -Recurse -Filter "*.vhdx" |
                Measure-Object -Property Length -Sum).Sum / 1GB
            Write-Host ("Total disk used by minikube: {0:N1} GB" -f $totalUsed)
        } else {
            Write-Host "Minikube directory not found: $minikubeDir"
        }
    ' 2>/dev/null || print_warning "Could not query VHDX files"
fi

# ============================================================================
# Docker Driver Resources (Vagrant VM)
# ============================================================================
if [[ "$ENV_TYPE" == "vagrant" ]] || [[ "$DRIVER" == "docker" ]]; then
    print_header "DOCKER CONTAINERS (MINIKUBE NODES)"

    if command -v docker &>/dev/null; then
        docker ps --filter "name=minikube" --format "table {{.Names}}\t{{.Status}}\t{{.Size}}" 2>/dev/null || \
            print_warning "Could not list Docker containers"

        echo ""
        echo "Docker disk usage:"
        docker system df 2>/dev/null || print_warning "Could not get Docker disk usage"
    else
        print_warning "Docker not available"
    fi
fi

# ============================================================================
# Kubernetes Cluster Resources
# ============================================================================
if kubectl cluster-info &>/dev/null; then
    print_header "KUBERNETES NODES"
    kubectl get nodes -o wide 2>/dev/null || print_warning "Could not list nodes"

    print_header "NODE RESOURCE USAGE"
    if kubectl top nodes &>/dev/null 2>&1; then
        kubectl top nodes
    else
        print_warning "Metrics not available (metrics-server may not be ready)"
        echo "Try: kubectl wait --for=condition=ready pod -l k8s-app=metrics-server -n kube-system"
    fi

    print_header "PERSISTENT VOLUMES"
    PV_COUNT=$(kubectl get pv --no-headers 2>/dev/null | wc -l)
    if [[ "$PV_COUNT" -gt 0 ]]; then
        kubectl get pv 2>/dev/null
    else
        echo "No persistent volumes found"
    fi

    print_header "PERSISTENT VOLUME CLAIMS (ALL NAMESPACES)"
    PVC_COUNT=$(kubectl get pvc -A --no-headers 2>/dev/null | wc -l)
    if [[ "$PVC_COUNT" -gt 0 ]]; then
        kubectl get pvc -A 2>/dev/null
    else
        echo "No persistent volume claims found"
    fi

    print_header "STORAGE CLASSES"
    kubectl get storageclass 2>/dev/null || echo "No storage classes found"

    print_header "POD RESOURCE USAGE (TOP 10)"
    if kubectl top pods -A &>/dev/null 2>&1; then
        kubectl top pods -A --sort-by=memory | head -11
    else
        print_warning "Metrics not available"
    fi

    # Ceph health check if installed
    if kubectl get namespace rook-ceph &>/dev/null 2>&1; then
        print_header "CEPH CLUSTER STATUS"
        kubectl -n rook-ceph get cephcluster 2>/dev/null || echo "Ceph cluster not found"

        echo ""
        echo "Ceph pods:"
        kubectl -n rook-ceph get pods --no-headers 2>/dev/null | head -10
        POD_COUNT=$(kubectl -n rook-ceph get pods --no-headers 2>/dev/null | wc -l)
        if [[ "$POD_COUNT" -gt 10 ]]; then
            echo "... and $((POD_COUNT - 10)) more pods"
        fi
    fi
else
    print_warning "Kubernetes cluster not accessible"
    echo "Make sure minikube is running: minikube start"
fi

# ============================================================================
# Summary
# ============================================================================
print_header "SUMMARY"
echo "Environment: $ENV_TYPE"
echo "Driver: $DRIVER"
echo "Profile: $PROFILE"

if kubectl cluster-info &>/dev/null; then
    NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
    POD_COUNT=$(kubectl get pods -A --no-headers 2>/dev/null | wc -l)
    echo "Nodes: $NODE_COUNT"
    echo "Total pods: $POD_COUNT"
fi

echo ""
print_info "For detailed Ceph status: ./components/ceph/scripts/status.sh"
print_info "For cluster health check: ./scripts/minikube/health-check.sh"
