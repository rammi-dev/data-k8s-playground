# Milvus Architecture

Milvus follows a **shared-storage disaggregated architecture** with four layers:

```
┌─────────────────────────────────────────────────────────────────┐
│                        ACCESS LAYER                             │
│  Proxy: gRPC/REST endpoint, auth, request routing, result merge │
│  Port 19530 (gRPC) / 9091 (metrics+health)                     │
├─────────────────────────────────────────────────────────────────┤
│                     COORDINATOR LAYER                           │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐       │
│  │ RootCoord│  │QueryCoord│  │DataCoord │  │IndexCoord│       │
│  │ DDL/DCL  │  │ query    │  │ data flow│  │ index    │       │
│  │ TSO      │  │ balance  │  │ segments │  │ builds   │       │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘       │
├─────────────────────────────────────────────────────────────────┤
│                       WORKER LAYER                              │
│  ┌──────────────────┐  ┌──────────────────┐                    │
│  │   Query Nodes     │  │   Data Nodes      │                   │
│  │ load segments     │  │ write buffer       │                   │
│  │ execute search    │  │ flush to storage   │                   │
│  │ ANN + filtering   │  │ compaction         │                   │
│  └──────────────────┘  └──────────────────┘                    │
├─────────────────────────────────────────────────────────────────┤
│                      STORAGE LAYER                              │
│  ┌──────────┐   ┌──────────────┐   ┌──────────────────┐       │
│  │  etcd    │   │  Ceph S3     │   │   Woodpecker     │       │
│  │ metadata │   │ segments     │   │ write-ahead log  │       │
│  │ schema   │   │ indexes      │   │ (replaces Pulsar)│       │
│  │ topology │   │ stats        │   │                  │       │
│  └──────────┘   └──────────────┘   └──────────────────┘       │
└─────────────────────────────────────────────────────────────────┘
```

## Coordinators

| Coordinator | Responsibility |
|-------------|---------------|
| **RootCoord** | DDL/DCL operations (create/drop collection), timestamp oracle (TSO), global ID allocation |
| **QueryCoord** | Manages query node segment loading, balances segments across query nodes, handles handoff from growing to sealed |
| **DataCoord** | Manages data node segment allocation, tracks segment lifecycle (growing, sealed, flushed), triggers compaction |
| **IndexCoord** | Schedules index builds on flushed segments, tracks build progress, manages index files in object storage |

## Data Flow

```
Insert --> Proxy --> WAL (Woodpecker) --> Data Node (buffer) --> Flush --> Ceph S3 (sealed segment)
                                                                             |
Query  --> Proxy --> Query Node --> search growing segments (in-memory)       v
                                --> search sealed segments (loaded from S3)
                                --> merge results --> return
```

1. **Insert**: Proxy assigns primary keys and timestamps, writes to Woodpecker WAL
2. **Buffer**: Data nodes consume WAL, buffer in growing segments (in-memory)
3. **Flush**: When segment reaches threshold (~512 MB), data node flushes to S3 as a sealed segment
4. **Index**: IndexCoord triggers index build on sealed segments; index files stored in S3
5. **Query**: Query nodes load sealed segments + indexes from S3, also search in-memory growing segments

## Segments

Segments are the fundamental data unit:

```
Collection
├── Shard 1
│   ├── Growing Segment (in-memory, receiving inserts)
│   ├── Sealed Segment (flushed to S3, indexed)
│   └── Sealed Segment (flushed to S3, indexed)
└── Shard 2
    ├── Growing Segment
    └── Sealed Segment
```

| State | Location | Searchable | Indexed |
|-------|----------|------------|---------|
| **Growing** | In-memory (data node) | Yes (brute-force) | No |
| **Sealed** | S3 (loaded into query node memory) | Yes | Yes (after index build) |
| **Flushed** | S3 (not loaded) | No (until loaded) | May be |

- **Seal threshold**: ~512 MB per segment (configurable)
- **Binlog format**: Segments stored as columnar binlog files (one file per field)
- **Compaction**: Merges small segments, applies deletes physically, reclaims space

## Partitions and Sharding

### Sharding (Automatic)

Collections are split into **shards**. Each shard is an independent write channel:
- Insert traffic distributes across shards by primary key hash
- More shards = higher write throughput in cluster mode

### Partitions (Manual)

Partitions sub-divide a collection for query efficiency:

```python
client.create_partition("my_collection", "2024")
client.create_partition("my_collection", "2025")

# Search within partition (skips other partitions entirely)
client.search("my_collection", data, partition_names=["2025"])
```

### Partition Key (Automatic Partitioning)

Auto-route inserts based on a field value:

```python
from pymilvus import CollectionSchema, FieldSchema, DataType

schema = CollectionSchema([
    FieldSchema("id", DataType.INT64, is_primary=True, auto_id=True),
    FieldSchema("tenant", DataType.VARCHAR, max_length=64, is_partition_key=True),
    FieldSchema("embedding", DataType.FLOAT_VECTOR, dim=768),
])
```

Queries filtered on the partition key field automatically prune irrelevant partitions.
