# Ceph Storage Component

Rook-Ceph provides distributed storage for Kubernetes using Ceph.

## Prerequisites

- Minikube cluster running with at least 3 nodes (for production-like setup)
- Additional raw block devices or directories for OSD storage

## Configuration

Enable Ceph in `config.yaml`:

```yaml
components:
  ceph:
    enabled: true
    namespace: "rook-ceph"
    chart_repo: "https://charts.rook.io/release"
    chart_name: "rook-ceph"
    chart_version: "v1.13.0"
```

Customize the Helm values in `helm/values.yaml`.

## Usage

### Deploy Ceph

```bash
cd /vagrant
./components/ceph/scripts/build.sh
```

### Check Status

```bash
kubectl -n rook-ceph get pods
kubectl -n rook-ceph get cephcluster
```

### Remove Ceph

```bash
./components/ceph/scripts/destroy.sh
```

## Architecture

This deployment uses Rook as the Ceph operator:

1. **Rook Operator** - Manages Ceph cluster lifecycle
2. **Ceph Monitors** - Maintain cluster state
3. **Ceph OSDs** - Store actual data
4. **Ceph MGR** - Provides monitoring and interfaces

## Storage Classes

After deployment, the following StorageClasses will be available:

- `rook-ceph-block` - Block storage (RBD)
- `rook-cephfs` - Shared filesystem (CephFS)
- `rook-ceph-bucket` - Object storage (S3-compatible)

## Notes

- For single-node minikube, Ceph runs in a degraded mode suitable for testing only
- Production deployments require multiple nodes and dedicated storage devices
