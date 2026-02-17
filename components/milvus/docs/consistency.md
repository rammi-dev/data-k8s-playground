# Milvus Consistency and ACID

## Consistency Levels

Milvus provides **tunable consistency** per operation. Every write gets a timestamp from the TSO (Timestamp Oracle in RootCoord). Reads specify a **guarantee timestamp** -- the system ensures all writes before that timestamp are visible.

| Level | Guarantee Timestamp | Latency | Use Case |
|-------|-------------------|---------|----------|
| **Strong** | Latest system timestamp | Highest | Financial, critical reads -- see every write immediately |
| **Bounded Staleness** | Latest - `graceful_time` (default 5s) | Medium | Dashboard queries -- tolerate seconds of delay |
| **Session** | Latest timestamp from this client session | Low | User-facing apps -- read-your-own-writes |
| **Eventually** | Earliest uncompleted timestamp | Lowest | Analytics, batch -- best throughput |

```
Timeline:  --T1--T2--T3--T4--T5--T6--T7--T8--T9--T10-->

Insert at T5:  record A

Strong read at T10:        sees A  (guarantee = T10)
Session read at T10:       sees A  (guarantee = T5, the session's last write)
Bounded read at T10:       sees A  (guarantee = T10 - 5s = T5, if within window)
Eventually read at T10:    may or may not see A (guarantee = earliest uncompleted)
```

Default: **Bounded Staleness** (best balance for most workloads).

### Per-Collection

```python
from pymilvus import MilvusClient, ConsistencyLevel

client = MilvusClient("http://localhost:19530")
client.create_collection(
    collection_name="my_collection",
    consistency_level=ConsistencyLevel.STRONG
)
```

### Per-Query Override

```python
results = client.search(
    collection_name="my_collection",
    data=[query_vector],
    consistency_level=ConsistencyLevel.SESSION
)
```

## ACID Properties

Milvus is **not a transactional database**. Here is what it guarantees:

| Property | Support | Details |
|----------|---------|---------|
| **Atomicity** | Partial | Single insert/delete operations are atomic. Batch inserts are NOT atomic -- a partial batch can succeed. DDL operations (create/drop collection) are atomic. |
| **Consistency** | Tunable | See consistency levels above. Not ACID consistency (constraint enforcement), but read consistency. No foreign keys, triggers, or check constraints. |
| **Isolation** | Snapshot | Reads see a consistent snapshot based on guarantee timestamp. No read/write transactions. Concurrent inserts to different segments do not conflict. |
| **Durability** | Yes | Once acknowledged, writes are in Woodpecker WAL and survive process restart. Sealed segments in S3 are durable on Ceph. etcd metadata uses synchronous writes. |

## Practical Implications

- **No multi-row transactions**: Cannot insert a vector and update metadata atomically
- **No rollback**: If a batch insert partially fails, the succeeded portion stays
- **Delete is logical**: Deletes create a delete log entry; physical removal happens during compaction
- **Upsert**: Supported via `upsert()` -- semantically delete-then-insert on the same primary key
- **Schema changes**: `add_field` and `drop_field` are online in v2.6 (no rebuild required for scalars; vectors need index rebuild)
