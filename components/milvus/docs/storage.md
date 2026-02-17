# Milvus Storage

## Three Storage Subsystems

| Subsystem | Backed By | Stores | Durability |
|-----------|-----------|--------|------------|
| **Meta Store** | etcd (5Gi PVC) | Collection schemas, partition info, segment metadata, index metadata, timestamps, topology | Synchronous writes, RAFT consensus |
| **Object Storage** | Ceph RGW (S3) | Sealed segments (binlog files), index files, statistics | Persisted to Ceph block storage via RGW |
| **Write-Ahead Log** | Woodpecker (10Gi PVC) | Ordered insert/delete log entries | Sequential writes, replayed on recovery |

## Ceph S3 Integration

This deployment uses Ceph RGW instead of the bundled MinIO:

| Setting | Value |
|---------|-------|
| Endpoint | `rook-ceph-rgw-s3-store.rook-ceph.svc:80` |
| Bucket | `milvus` |
| User | `CephObjectStoreUser/milvus` |
| Secret | `rook-ceph-object-user-s3-store-milvus` |

Credentials are injected at install time by `build.sh` via `--set` (not stored in values files). The `externalS3` chart config replaces the MinIO subchart entirely.

## Woodpecker WAL (v2.6+)

Woodpecker replaces Pulsar/Kafka as the write-ahead log:
- Cloud-native, lightweight -- no external message broker needed
- Sequential write performance optimized
- Entries replayed on recovery to rebuild growing segments
- Reduced operational complexity vs Pulsar (which required ZooKeeper + BookKeeper)

## Storage Sizing (This Deployment)

| Component | PVC Size | StorageClass | Usage |
|-----------|----------|--------------|-------|
| Milvus | 10Gi | rook-ceph-block | Woodpecker WAL, local cache |
| etcd | 5Gi | rook-ceph-block | Metadata (typically < 100 MB) |
| Ceph S3 | Shared pool | Ceph RGW | Segments, indexes, stats |
