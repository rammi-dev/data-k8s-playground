# Milvus Scaling and Monitoring

## Standalone vs Cluster

| Aspect | Standalone | Cluster (This Deployment) |
|--------|------------|---------------------------|
| Topology | All components in 1 pod | Separate pods per component |
| Max vectors | ~10-50M (depends on dims) | Billions |
| Throughput | Single-node bound | Horizontal scale-out |
| HA | No (single point of failure) | Yes (component-level redundancy) |
| Complexity | Low | Higher (many pods) |

## Resource Sizing Guidelines

| Scale | Vectors | Dimensions | Memory Needed | Recommended Mode |
|-------|---------|------------|---------------|-----------------|
| Small | < 1M | 768 | ~3-6 GB | Standalone |
| Medium | 1-10M | 768 | ~6-30 GB | Standalone (beefy) or Cluster |
| Large | 10-100M | 768 | ~30-300 GB | Cluster |
| XL | 100M+ | 768 | 300+ GB | Cluster with DiskANN |

Memory formula (approximate):

```
memory = num_vectors x dim x 4 bytes x index_overhead
         + num_vectors x scalar_fields_size

index_overhead:
  FLAT  = 1.0
  HNSW  = 1.5 (M=16)
  IVF   = 1.05
```

## Scaling Components

Scale individual components in `values-overrides.yaml`:

```yaml
milvus:
  queryNode:
    replicas: 2
    resources:
      requests:
        memory: 8Gi
  dataNode:
    replicas: 2
  indexNode:
    replicas: 1
  proxy:
    replicas: 2
```

Data in S3 and etcd is shared -- scaling is a replica count change, no data migration.

## Monitoring

### Health Endpoint

```bash
curl http://localhost:9091/healthz
curl http://localhost:9091/api/v1/health
```

### Prometheus Metrics

Exposed at `http://localhost:9091/metrics`.

| Metric | Description | Alert Threshold |
|--------|-------------|-----------------|
| `milvus_proxy_search_vectors_count` | Total search requests | Monitor trend |
| `milvus_proxy_insert_vectors_count` | Total insert count | Monitor trend |
| `milvus_proxy_sq_latency_bucket` | Search/query latency histogram | p99 > 500ms |
| `milvus_querynode_sq_segment_latency` | Per-segment search latency | Outliers = hot segments |
| `milvus_datanode_flush_segment_count` | Segments flushed | Compaction health |
| `milvus_querynode_entity_num` | Loaded entities per query node | Memory pressure |
| `milvus_rootcoord_ddl_count` | DDL operations count | Schema change tracking |
| `process_resident_memory_bytes` | Process RSS | Approaching limits |

### Port-Forward

```bash
kubectl -n milvus port-forward svc/milvus 9091:9091
curl http://localhost:9091/metrics | head -50
```
