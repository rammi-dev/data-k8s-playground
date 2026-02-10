# Minikube Scripts

Scripts for managing minikube Kubernetes clusters. Supports multiple deployment modes:
- **Vagrant + Docker**: Minikube runs inside a Vagrant VM using Docker driver
- **Windows + Hyper-V**: Minikube runs directly on Windows using Hyper-V driver

## Quick Start

```bash
# Option 1: From inside the Vagrant VM (Docker driver)
cd /vagrant
./scripts/minikube/build.sh

# Option 2: From Windows/WSL (Hyper-V driver)
minikube start --driver=hyperv --nodes=3 --cpus=4 --memory=8g

# Check resources and cluster health
./scripts/minikube/check-resources.sh

# Access Kubernetes dashboard
./scripts/minikube/access-dashboard.sh
```

## Hyper-V Driver (Windows Native)

When using minikube with Hyper-V on Windows, understanding where VMs are stored and how to monitor them is important.

### VM Storage Location

```
C:\Users\<username>\.minikube\machines\<profile-name>\
├── <profile-name>.vhdx    # Virtual hard disk (grows dynamically)
├── config.json            # VM configuration
└── ...
```

For a multi-node cluster:
```
C:\Users\<username>\.minikube\machines\
├── minikube\           # Control plane node
│   └── minikube.vhdx
├── minikube-m02\       # Worker node 2
│   └── minikube-m02.vhdx
└── minikube-m03\       # Worker node 3
    └── minikube-m03.vhdx
```

### VM Operating System

Minikube uses **Buildroot Linux** - a minimal Linux distribution (~200MB) specifically designed for embedded systems. It includes only what's needed to run Kubernetes:
- Docker/containerd runtime
- kubelet, kubeadm
- Minimal shell utilities

### Monitoring Hyper-V VMs

**PowerShell commands:**
```powershell
# List all minikube VMs
Get-VM | Where-Object { $_.Name -like "minikube*" }

# Get detailed VM info (CPU, memory, state)
Get-VM minikube | Select-Object Name, State, CPUUsage,
    @{N='MemoryAssigned(GB)';E={$_.MemoryAssigned/1GB}},
    @{N='MemoryDemand(GB)';E={$_.MemoryDemand/1GB}}

# Check virtual disk size
Get-VHD "C:\Users\$env:USERNAME\.minikube\machines\minikube\minikube.vhdx" |
    Select-Object Path,
    @{N='Size(GB)';E={$_.Size/1GB}},
    @{N='FileSize(GB)';E={$_.FileSize/1GB}}

# Get all minikube VHDs with sizes
Get-ChildItem "$env:USERPROFILE\.minikube\machines" -Recurse -Filter "*.vhdx" |
    ForEach-Object {
        Get-VHD $_.FullName | Select-Object Path,
        @{N='Allocated(GB)';E={[math]::Round($_.Size/1GB,2)}},
        @{N='Used(GB)';E={[math]::Round($_.FileSize/1GB,2)}}
    }
```

**Hyper-V Manager:**
1. Open Hyper-V Manager (`virtmgmt.msc`)
2. VMs appear as `minikube`, `minikube-m02`, etc.
3. Right-click → Settings to view CPU/Memory
4. Right-click → Checkpoint for snapshots

### Hyper-V vs Docker Driver Comparison

| Aspect | Hyper-V | Docker (in Vagrant) |
|--------|---------|---------------------|
| **Performance** | Native hypervisor | Nested virtualization |
| **Storage** | VHDX (dynamic) | Docker volumes |
| **Networking** | Virtual Switch | Docker bridge |
| **Multi-node** | Separate VMs | Docker containers |
| **Resource isolation** | Full VM isolation | Container isolation |
| **Startup time** | ~60-90 seconds | ~30-45 seconds |
| **Best for** | Production-like testing | Development speed |

## Scripts

| Script | Description |
|--------|-------------|
| `build.sh` | Start minikube cluster with configured resources and addons |
| `check-resources.sh` | Check VM resources, storage usage, and cluster health |
| `health-check.sh` | Quick cluster and Ceph health verification |
| `status.sh` | Show minikube status and addons |
| `access-dashboard.sh` | Open Kubernetes dashboard in browser |
| `destroy.sh` | Delete minikube cluster and clean up |

## Configuration

Minikube settings are in `config.yaml`:

```yaml
minikube:
  driver: "docker"
  nodes: 1              # Increase for multi-node cluster
  cpus: "max"           # Use all available CPUs
  memory: "max"         # Use all available memory
  disk_size: "40g"
  kubernetes_version: "v1.28.0"
  extra_config:
    - "kubelet.housekeeping-interval=10s"
```

## Enabled Addons

The `build.sh` script automatically enables these addons:

| Addon | Purpose |
|-------|---------|
| **ingress** | NGINX Ingress Controller for HTTP/HTTPS routing |
| **ingress-dns** | DNS for ingress hostnames |
| **dashboard** | Kubernetes web UI |
| **metrics-server** | Resource metrics for `kubectl top pods/nodes` |
| **registry** | Local container registry for multi-node image distribution |
| **metallb** | LoadBalancer service support with dynamic IP range |

Note: Storage addons (csi-hostpath-driver, storage-provisioner) are skipped when deploying Ceph, as Rook-Ceph provides its own CSI drivers and storage classes.

## Common Commands

```bash
# Check cluster status
minikube status

# View enabled addons
minikube addons list | grep enabled

# Get node resources
kubectl top nodes

# Get pod resources
kubectl top pods -A

# Stop cluster (preserves state)
minikube stop

# Delete cluster completely
minikube delete
```

## Multi-Node Cluster

To run a multi-node cluster (e.g., for Ceph testing):

1. Edit `config.yaml`:
   ```yaml
   minikube:
     nodes: 3
   ```

2. Rebuild minikube:
   ```bash
   minikube delete
   ./scripts/minikube/build.sh
   ```

## Storage Classes

After `build.sh` and Ceph deployment, these storage classes are available:

```bash
kubectl get storageclass
```

| StorageClass | Provisioner | Purpose |
|--------------|-------------|---------|
| `standard` | minikube hostpath | Default minikube storage |
| `ceph-block` | Ceph RBD CSI | Block storage for databases, stateful apps |
| `ceph-bucket` | Ceph RGW | S3-compatible object storage |

See [components/ceph/README.md](../../components/ceph/README.md) for Ceph storage details.

## Troubleshooting

### Cluster won't start
```bash
# Check minikube logs
minikube logs

# Delete and recreate
minikube delete
./scripts/minikube/build.sh
```

### Metrics not available
```bash
# Wait for metrics-server to be ready
kubectl wait --for=condition=ready pod -l k8s-app=metrics-server -n kube-system --timeout=120s

# Then try again
kubectl top nodes
```

### Dashboard not opening
```bash
# Get dashboard URL manually
minikube dashboard --url
```
