#!/bin/bash
# Load config.yaml into shell variables
# Usage: source config-loader.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG_FILE="$PROJECT_ROOT/config.yaml"

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Error: config.yaml not found at $CONFIG_FILE" >&2
    exit 1
fi

# Check for yq command
if command -v yq &> /dev/null; then
    YQ_CMD="yq"
elif command -v yq.exe &> /dev/null; then
    YQ_CMD="yq.exe"
else
    echo "Warning: yq not found, using fallback grep/sed parsing" >&2
    YQ_CMD=""
fi

# Load config value using yq or fallback
load_config() {
    local path="$1"
    local default="$2"

    if [[ -n "$YQ_CMD" ]]; then
        local value
        value=$($YQ_CMD eval "$path // \"\"" "$CONFIG_FILE" 2>/dev/null)
        if [[ -n "$value" && "$value" != "null" ]]; then
            echo "$value"
        else
            echo "$default"
        fi
    else
        echo "$default"
    fi
}

# VM Configuration
VM_CPUS=$(load_config '.vm.cpus' '4')
VM_MEMORY=$(load_config '.vm.memory' '8192')
VM_DISK_SIZE=$(load_config '.vm.disk_size' '50')
VM_BOX=$(load_config '.vm.box' 'ubuntu/jammy64')
VM_NAME=$(load_config '.vm.name' 'data-playground')

# Paths Configuration
HOST_PROJECT_PATH=$(load_config '.paths.host_project_path' '/mnt/c/Work/playground')
HOST_DATA_PATH=$(load_config '.paths.host_data_path' '/mnt/c/Work/playground/data')
GUEST_PROJECT_PATH=$(load_config '.paths.guest_project_path' '/vagrant')
GUEST_DATA_PATH=$(load_config '.paths.guest_data_path' '/data')

# Reserved resources for Linux OS + Docker (do not give to minikube)
RESERVED_CPUS=$(load_config '.reserved.cpus' '1')
RESERVED_MEMORY=$(load_config '.reserved.memory' '2048')

# Minikube Configuration
MINIKUBE_DRIVER=$(load_config '.minikube.driver' 'docker')
MINIKUBE_NODES=$(load_config '.minikube.nodes' '1')
MINIKUBE_DISK_SIZE=$(load_config '.minikube.disk_size' '40g')
MINIKUBE_K8S_VERSION=$(load_config '.minikube.kubernetes_version' 'v1.28.0')

# Calculate minikube resources: (VM - reserved) / nodes
# minikube --cpus and --memory are PER NODE
MINIKUBE_TOTAL_CPUS=$((VM_CPUS - RESERVED_CPUS))
MINIKUBE_TOTAL_MEMORY=$((VM_MEMORY - RESERVED_MEMORY))
MINIKUBE_CPUS=$((MINIKUBE_TOTAL_CPUS / MINIKUBE_NODES))
MINIKUBE_MEMORY=$((MINIKUBE_TOTAL_MEMORY / MINIKUBE_NODES))

# Ensure minimum viable resources per node (minikube requires at least 2 CPUs, 2GB per node)
if [[ $MINIKUBE_CPUS -lt 2 ]]; then
    echo "Warning: Calculated per-node CPUs ($MINIKUBE_CPUS) too low, using minimum of 2" >&2
    echo "  Total available: $MINIKUBE_TOTAL_CPUS CPUs for $MINIKUBE_NODES nodes" >&2
    MINIKUBE_CPUS=2
fi
if [[ $MINIKUBE_MEMORY -lt 2048 ]]; then
    echo "Warning: Calculated per-node memory ($MINIKUBE_MEMORY MB) too low, using minimum of 2048MB" >&2
    echo "  Total available: $MINIKUBE_TOTAL_MEMORY MB for $MINIKUBE_NODES nodes" >&2
    MINIKUBE_MEMORY=2048
fi

# Load extra config as space-separated string
if [[ -n "$YQ_CMD" ]]; then
    MINIKUBE_EXTRA_CONFIG=$($YQ_CMD eval '.minikube.extra_config // [] | join(" ")' "$CONFIG_FILE" 2>/dev/null)
else
    MINIKUBE_EXTRA_CONFIG=""
fi

# Component: Ceph
CEPH_ENABLED=$(load_config '.components.ceph.enabled' 'false')
CEPH_NAMESPACE=$(load_config '.components.ceph.namespace' 'rook-ceph')
CEPH_CHART_REPO=$(load_config '.components.ceph.chart_repo' 'https://charts.rook.io/release')
CEPH_CHART_NAME=$(load_config '.components.ceph.chart_name' 'rook-ceph')
CEPH_CHART_VERSION=$(load_config '.components.ceph.chart_version' 'v1.13.0')

# Export all variables
export VM_CPUS VM_MEMORY VM_DISK_SIZE VM_BOX VM_NAME
export RESERVED_CPUS RESERVED_MEMORY
export HOST_PROJECT_PATH HOST_DATA_PATH GUEST_PROJECT_PATH GUEST_DATA_PATH
export MINIKUBE_DRIVER MINIKUBE_NODES MINIKUBE_CPUS MINIKUBE_MEMORY MINIKUBE_DISK_SIZE MINIKUBE_K8S_VERSION MINIKUBE_EXTRA_CONFIG
export CEPH_ENABLED CEPH_NAMESPACE CEPH_CHART_REPO CEPH_CHART_NAME CEPH_CHART_VERSION
export PROJECT_ROOT CONFIG_FILE
