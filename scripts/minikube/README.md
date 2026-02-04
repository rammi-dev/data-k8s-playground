# Minikube Scripts

Scripts for managing the minikube Kubernetes cluster inside the Vagrant VM.

## Quick Start

```bash
# From inside the Vagrant VM
cd /vagrant

# Start minikube cluster
./scripts/minikube/build.sh

# Access Kubernetes dashboard
./scripts/minikube/access-dashboard.sh
```

## Scripts

| Script | Description |
|--------|-------------|
| `build.sh` | Start minikube cluster with configured resources and addons |
| `health-check.sh` | Quick cluster and Ceph health verification |
| `status.sh` | Show minikube status and addons |
| `access-dashboard.sh` | Open Kubernetes dashboard in browser |

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
| **csi-hostpath-driver** | Persistent storage with CSI (StorageClass: `csi-hostpath-sc`) |
| **dashboard** | Kubernetes web UI |
| **metrics-server** | Resource metrics for `kubectl top pods/nodes` |

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

After `build.sh` completes, these storage classes are available:

```bash
kubectl get storageclass
```

| StorageClass | Provisioner | Binding Mode |
|--------------|-------------|--------------|
| `standard` | minikube hostpath | Immediate |
| `csi-hostpath-sc` | CSI hostpath | Immediate |

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
