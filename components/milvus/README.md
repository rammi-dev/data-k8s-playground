# Milvus Vector Database

Vector database for similarity search and AI applications. Deployed in **cluster mode** on Rook-Ceph (block storage + S3 via RGW).

| Property | Value |
|----------|-------|
| Version | v2.6.8 |
| Helm Chart | zilliztech/milvus 4.0.31 |
| Mode | Cluster (separate coordinator + worker pods) |
| Object Storage | Ceph RGW (S3-compatible) |
| Block Storage | rook-ceph-block |
| gRPC Port | 19530 |
| Namespace | milvus |

## Prerequisites

- Kubernetes cluster accessible via kubectl
- Ceph deployed with block storage + S3 object store (`./components/ceph/scripts/build.sh`)
- `components.milvus.enabled: true` in config.yaml

## Usage

```bash
# Deploy
./scripts/build.sh

# Destroy
./scripts/destroy.sh

# Test
./scripts/test/test-milvus.sh

# Render templates for inspection
./scripts/regenerate-rendered.sh [--clean]
```

## Connect

```bash
kubectl -n milvus port-forward svc/milvus 19530:19530
```

```python
from pymilvus import MilvusClient
client = MilvusClient("http://localhost:19530")
client.list_collections()
```

## Docs

| Document | Content |
|----------|---------|
| [Architecture](docs/architecture.md) | 4-layer architecture, coordinators, data flow, segments |
| [Storage](docs/storage.md) | etcd, Ceph S3, Woodpecker WAL, segment lifecycle, sizing |
| [Data Types & Indexes](docs/data-types.md) | Scalar/vector types, index types, distance metrics |
| [Consistency & ACID](docs/consistency.md) | 4 consistency levels, ACID guarantees, transactions |
| [Scaling & Monitoring](docs/scaling.md) | Standalone vs cluster, resource sizing, Prometheus metrics |

## File Structure

```
components/milvus/
├── README.md
├── docs/
│   ├── architecture.md
│   ├── storage.md
│   ├── data-types.md
│   ├── consistency.md
│   └── scaling.md
├── helm/
│   ├── Chart.yaml                  # Helm wrapper (depends on zilliztech/milvus)
│   ├── values.yaml                 # Base values (standalone, MinIO, Woodpecker)
│   └── values-overrides.yaml       # Overrides: cluster mode + Ceph S3
├── manifests/
│   └── s3-user.yaml                # CephObjectStoreUser for Milvus
├── deployment/
│   ├── .gitignore
│   └── rendered/                   # Output of regenerate-rendered.sh
└── scripts/
    ├── build.sh                    # Deploy (S3 user + bucket + Helm)
    ├── destroy.sh                  # Teardown (Helm + PVCs + S3 user)
    ├── regenerate-rendered.sh
    └── test/
        └── test-milvus.sh
```
