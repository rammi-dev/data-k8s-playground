# PostgreSQL (CloudNativePG)

CloudNativePG operator for deploying and managing PostgreSQL databases on Kubernetes. Provides high availability, automated failover, backups, and monitoring.

## Overview

**CloudNativePG** is a Kubernetes operator that manages the full lifecycle of PostgreSQL clusters using a declarative approach. It follows the same operator pattern as Strimzi (Kafka) and Knative in this playground.

**Key Features:**
- **High Availability**: Automatic failover with streaming replication
- **Backups**: Continuous archiving and point-in-time recovery (PITR) with S3 support
- **Monitoring**: Built-in Prometheus metrics
- **Self-Healing**: Automatic pod recreation and replica synchronization
- **Cloud Native**: Uses Kubernetes-native resources (CRDs, operators, controllers)

**Docker Images** (from ghcr.io - free and open source):
- Operator: `ghcr.io/cloudnative-pg/cloudnative-pg`
- PostgreSQL: `ghcr.io/cloudnative-pg/postgresql` (Debian-based, weekly security updates)

## API Reference

- [CloudNativePG API Reference (v1.28)](https://cloudnative-pg.io/docs/1.28/cloudnative-pg.v1) — Cluster, Backup, ScheduledBackup, Pooler, Database CRDs

## Prerequisites

- Kubernetes cluster running (minikube or production)
- Ceph deployed for persistent storage (`./components/ceph/scripts/build.sh`)
- StorageClass `rook-ceph-block` available

## Quick Start

```bash
# 1. Deploy operator only
./scripts/build.sh

# 2. (Optional) Deploy test cluster
./scripts/tests/deploy-test-cluster.sh

# 3. Connect to PostgreSQL (if test cluster deployed)
kubectl exec -it -n postgres-operator test-cluster-1 -- psql -U app

# 4. Get password (if test cluster deployed)
kubectl get secret test-cluster-app -n postgres-operator -o jsonpath='{.data.password}' | base64 -d
```

## Component Structure

```
components/postgres/
├── README.md                    # Comprehensive documentation
├── helm/
│   ├── Chart.yaml              # Wrapper chart with cloudnative-pg dependency
│   ├── values.yaml             # Operator configuration
│   ├── values-overrides.yaml   # Playground-specific overrides
│   └── manifests/
│       ├── test-cluster.yaml        # Single-node test cluster
│       └── test-cluster-s3.yaml     # HA cluster with S3 backups (optional)
└── scripts/
    ├── build.sh                # Deploy operator only
    ├── destroy.sh              # Complete removal
    ├── regenerate-rendered.sh  # Render Helm templates to files (for inspection)
    └── tests/
        └── deploy-test-cluster.sh  # Deploy test PostgreSQL cluster (optional)
```

## Creating PostgreSQL Instances

### Test Cluster (Included)

The test cluster is automatically deployed by `build.sh`:
- **Name**: `test-cluster`
- **Instances**: 1 (single-node for development)
- **Storage**: 5Gi on `rook-ceph-block`
- **Database**: `app`
- **User**: `app`

### Production Instances

Create custom PostgreSQL clusters by defining a `Cluster` CR:

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: my-app-db
  namespace: my-app
spec:
  instances: 3  # HA with 3 replicas
  imageName: ghcr.io/cloudnative-pg/postgresql:17.2
  
  storage:
    storageClass: rook-ceph-block
    size: 20Gi
  
  resources:
    requests:
      memory: "1Gi"
      cpu: "500m"
    limits:
      memory: "2Gi"
      cpu: "1000m"
  
  bootstrap:
    initdb:
      database: myapp
      owner: myapp
```

Apply with:
```bash
kubectl apply -f my-app-db.yaml -n my-app
```

## S3 Backups with Ceph

CloudNativePG supports continuous archiving to S3-compatible storage (Ceph RGW).

### 1. Create S3 User in Ceph

```bash
# Apply CephObjectStoreUser manifest
cat <<EOF | kubectl apply -f -
apiVersion: ceph.rook.io/v1
kind: CephObjectStoreUser
metadata:
  name: postgres-backups
  namespace: rook-ceph
spec:
  store: s3-store
  displayName: "PostgreSQL Backups User"
EOF

# Wait for secret to be created
kubectl wait --for=jsonpath='{.status.phase}'=Ready \
  cephobjectstoreuser/postgres-backups -n rook-ceph --timeout=60s
```

### 2. Create S3 Credentials Secret

```bash
# Get S3 credentials from Ceph
ACCESS_KEY=$(kubectl get secret -n rook-ceph rook-ceph-object-user-s3-store-postgres-backups \
  -o jsonpath='{.data.AccessKey}' | base64 -d)
SECRET_KEY=$(kubectl get secret -n rook-ceph rook-ceph-object-user-s3-store-postgres-backups \
  -o jsonpath='{.data.SecretKey}' | base64 -d)

# Create secret in postgres namespace
kubectl create secret generic postgres-s3-creds \
  -n postgres-operator \
  --from-literal=ACCESS_KEY_ID="$ACCESS_KEY" \
  --from-literal=SECRET_ACCESS_KEY="$SECRET_KEY"
```

### 3. Deploy Cluster with Backups

See `helm/templates/custom/test-cluster-s3.yaml` for a complete example with:
- Continuous WAL archiving to S3
- Scheduled daily backups
- 30-day retention policy
- Compression and encryption

## Connection Information

### Service Endpoints

CloudNativePG creates two services per cluster:

- **Read-Write** (primary): `<cluster-name>-rw.<namespace>.svc.cluster.local:5432`
- **Read-Only** (replicas): `<cluster-name>-ro.<namespace>.svc.cluster.local:5432`

For test cluster:
```
test-cluster-rw.postgres-operator.svc.cluster.local:5432
```

### Credentials

Credentials are stored in a secret named `<cluster-name>-app`:

```bash
# Get password
kubectl get secret test-cluster-app -n postgres-operator \
  -o jsonpath='{.data.password}' | base64 -d

# Get username (default: app)
kubectl get secret test-cluster-app -n postgres-operator \
  -o jsonpath='{.data.username}' | base64 -d
```

### Connection String

```
postgresql://app:<password>@test-cluster-rw.postgres-operator.svc.cluster.local:5432/app
```

## Monitoring

CloudNativePG exposes Prometheus metrics on port 9187.

### Check Cluster Status

```bash
# Get cluster status
kubectl get cluster -n postgres-operator

# Describe cluster
kubectl describe cluster test-cluster -n postgres-operator

# View logs
kubectl logs -n postgres-operator test-cluster-1
```

### Cluster Health

```bash
# Check replication status (for HA clusters)
kubectl exec -it -n postgres-operator test-cluster-1 -- \
  psql -U postgres -c "SELECT * FROM pg_stat_replication;"

# Check database size
kubectl exec -it -n postgres-operator test-cluster-1 -- \
  psql -U app -c "SELECT pg_size_pretty(pg_database_size('app'));"
```

## High Availability

For production, deploy with 3+ instances:

```yaml
spec:
  instances: 3
  
  # Synchronous replication for zero data loss
  postgresql:
    synchronous:
      method: any
      number: 1
```

CloudNativePG automatically:
- Elects a new primary if the current one fails
- Recreates failed replicas
- Synchronizes data to new replicas

## Teardown

```bash
# Remove operator and all PostgreSQL clusters
./scripts/destroy.sh
```

**Warning**: This deletes all PostgreSQL databases and their data!

## Troubleshooting

### Cluster Not Ready

```bash
# Check cluster status
kubectl describe cluster test-cluster -n postgres-operator

# Check operator logs
kubectl logs -n postgres-operator -l app.kubernetes.io/name=cloudnative-pg

# Check pod events
kubectl get events -n postgres-operator --sort-by='.lastTimestamp'
```

### Connection Issues

```bash
# Verify service exists
kubectl get svc -n postgres-operator

# Test from another pod
kubectl run -it --rm psql-test --image=postgres:17 --restart=Never -- \
  psql -h test-cluster-rw.postgres-operator.svc.cluster.local -U app
```

### Storage Issues

```bash
# Check PVCs
kubectl get pvc -n postgres-operator

# Check StorageClass
kubectl get sc rook-ceph-block
```

## Resources

- [CloudNativePG Documentation](https://cloudnative-pg.io/documentation/)
- [GitHub Repository](https://github.com/cloudnative-pg/cloudnative-pg)
- [Helm Chart](https://github.com/cloudnative-pg/charts)
- [Container Images](https://github.com/cloudnative-pg/postgres-containers)
