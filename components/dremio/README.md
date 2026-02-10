# Dremio Enterprise

Dremio EE v26.1 deployed on Kubernetes via Helm chart (`oci://quay.io/dremio/dremio-helm:3.2.3`) with Ceph S3 (RGW) as the storage backend.

## Prerequisites

- Kubernetes cluster running (minikube or production)
- Ceph S3 deployed (`./components/ceph/scripts/build.sh`)
- Quay.io registry credentials (for pulling Dremio images)
- `.env` file configured (see below)

## Configuration

### .env File

```bash
cp helm/.env.example helm/.env
# Edit helm/.env with your credentials:
```

| Variable | Required | Description |
|----------|----------|-------------|
| `DREMIO_REGISTRY_USER` | Yes | Quay.io username |
| `DREMIO_REGISTRY_PASSWORD` | Yes | Quay.io password |
| `DREMIO_REGISTRY_EMAIL` | No | Registry email (default: `no-reply@dremio.local`) |
| `DREMIO_LICENSE_KEY` | No | Enterprise license key (trial mode without) |
| `DREMIO_MONGODB_PASSWORD` | Yes | MongoDB app user password |

### Values Overrides

All Dremio configuration is in `helm/values-overrides.yaml`. This file overrides the chart defaults without modifying any chart templates. Key sections:

| Section | Purpose |
|---------|---------|
| `coordinator` | Resources, replicas, web auth |
| `engine` | Engine sizes, CPU capacities, storage options (shown in UI) |
| `catalog` | Polaris catalog server, S3 storage config |
| `mongodb` | Replica count, resources, storage |
| `distStorage` | S3 bucket, endpoint, credentials |

## Deployment Modes

### Dev Mode (current)

The Dremio Helm chart is extracted locally at `helm/dremio/`. This allows inspecting and understanding chart templates without modifying them.

```bash
# Chart was pulled from OCI:
helm pull oci://quay.io/dremio/dremio-helm --version 3.2.3 --untar -d helm/
```

Build script uses the local chart:
```bash
helm upgrade --install dremio helm/dremio/ \
    -f helm/values-overrides.yaml \
    --set distStorage.aws.credentials.accessKey=... \
    ...
```

### Production Mode

Use the OCI chart reference directly — no local extraction needed:

```bash
helm upgrade --install dremio oci://quay.io/dremio/dremio-helm \
    --version 3.2.3 \
    -n dremio \
    -f values-overrides.yaml \
    --set distStorage.aws.credentials.accessKey=... \
    --set catalog.storage.s3.accessKey=... \
    ...
```

`values-overrides.yaml` works identically with both modes. All configuration changes go in this file — never modify chart templates.

### What build.sh Does Before Helm Install

1. **Applies S3 user manifests** to `rook-ceph` namespace (`helm/templates/custom/s3-users/`)
2. **Waits** for Rook to generate S3 credential secrets
3. **Retrieves** separate S3 credentials (admin, dremio-dist, dremio-catalog)
4. **Creates buckets** using admin credentials
5. **Pre-creates secrets** in `dremio` namespace:
   - `catalog-server-s3-storage-creds` — catalog S3 credentials
   - `dremio-mongodb-app-users` — MongoDB password from `.env`
   - `dremio-quay-secret` — Docker registry credentials
6. **Runs `helm upgrade --install`** with distStorage and catalog credentials via `--set`

In production, steps 1-5 can be handled by CI/CD or a Kubernetes operator. The Helm install (step 6) is the same regardless of deployment mode.

## Custom Manifests

Custom Kubernetes resources that belong to Dremio but are applied to other namespaces:

```
helm/templates/custom/
  s3-users/
    dremio-dist.yaml      # CephObjectStoreUser for distStorage (rook-ceph ns)
    dremio-catalog.yaml   # CephObjectStoreUser for catalog (rook-ceph ns)
```

These are applied by `build.sh` via `kubectl apply -R -f` before the Helm install. They create S3 users in Ceph whose credential secrets are then retrieved and injected into Dremio.

## Engines

Engines are **not** managed by Helm. They must be created through the Dremio UI:

1. Login at `http://localhost:9047`
2. Go to Settings > Engines > Add Engine
3. Recommended starting config:
   - Size: Small (1 pod, 10Gi memory)
   - CPU: 1C
   - Resource Allocation: reserve-0-0

The engine operator (deployed by the chart) handles executor pod lifecycle automatically.

## Quick Start

```bash
# 1. Configure credentials
cp helm/.env.example helm/.env
# Edit helm/.env

# 2. Deploy
./scripts/build.sh

# 3. Access UI
./scripts/dashboard.sh

# 4. Create admin user (first login)
# 5. Create an engine via UI
```

## Teardown

```bash
./scripts/destroy.sh
```

## Related Documentation

- [STORAGE.md](docs/STORAGE.md) — S3 buckets, PVCs, users & credentials, all secrets
- [MONGODB.md](docs/MONGODB.md) — MongoDB setup, Kubernetes objects, backup & restore
