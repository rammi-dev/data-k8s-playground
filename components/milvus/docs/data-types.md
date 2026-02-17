# Milvus Data Types and Indexes

## Scalar Types

| Type | Description | Use Case |
|------|-------------|----------|
| `BOOL` | Boolean | Flags, filters |
| `INT8` | 8-bit signed integer | Small enums |
| `INT16` | 16-bit signed integer | Compact numeric |
| `INT32` | 32-bit signed integer | IDs, counts |
| `INT64` | 64-bit signed integer | Primary keys (auto-ID default), timestamps |
| `FLOAT` | 32-bit IEEE 754 | Scores, measurements |
| `DOUBLE` | 64-bit IEEE 754 | High-precision numeric |
| `VARCHAR` | Variable-length string (max 65535 bytes) | Text fields, metadata |
| `JSON` | JSON document | Flexible schema, nested filtering |
| `ARRAY` | Typed array (`ARRAY<INT32>`, etc.) | Multi-value attributes |

## Vector Types

| Type | Element | Dimensions | Storage per Vector | Use Case |
|------|---------|------------|-------------------|----------|
| `FLOAT_VECTOR` | float32 | 1-32,768 | dim x 4 bytes | Standard embeddings (OpenAI, Sentence Transformers) |
| `FLOAT16_VECTOR` | float16 | 1-32,768 | dim x 2 bytes | Memory-efficient, minimal accuracy loss |
| `BFLOAT16_VECTOR` | bfloat16 | 1-32,768 | dim x 2 bytes | ML training-compatible format |
| `BINARY_VECTOR` | bit | 8-32,768 (x8) | dim / 8 bytes | Hash-based embeddings, SimHash |
| `SPARSE_FLOAT_VECTOR` | float32 (sparse) | No fixed limit | nnz x 8 bytes | BM25, SPLADE, learned sparse |

## Index Types

| Index | Vector Type | Build Time | Query Speed | Memory | Best For |
|-------|-------------|------------|-------------|--------|----------|
| `FLAT` | Dense | None | Slow (brute-force) | dim x 4B x N | < 10K vectors, exact results |
| `IVF_FLAT` | Dense | Fast | Medium | ~1.05x raw | 100K-1M, recall-critical |
| `IVF_SQ8` | Dense | Fast | Medium-Fast | ~0.25x raw | 1M+, memory-constrained |
| `IVF_PQ` | Dense | Medium | Fast | ~0.05x raw | 10M+, memory-critical |
| `HNSW` | Dense | Slow | Very Fast | ~1.5x raw | Low-latency, high-recall |
| `DISKANN` | Dense | Medium | Fast | Small (disk) | Billion-scale, disk-resident |
| `SPARSE_INVERTED_INDEX` | Sparse | Fast | Fast | ~nnz x 12B | Sparse vectors |
| `SPARSE_WAND` | Sparse | Fast | Faster | ~nnz x 12B | Sparse top-K acceleration |

## Distance Metrics

| Metric | Range | Vector Type | Use Case |
|--------|-------|-------------|----------|
| `L2` | [0, inf) | Dense | General similarity (lower = closer) |
| `IP` | (-inf, inf) | Dense | Normalized embeddings (higher = closer) |
| `COSINE` | [0, 2] | Dense | Text/NLP (angle-based, lower = closer) |
| `HAMMING` | [0, dim] | Binary | Hash similarity |
| `JACCARD` | [0, 1] | Binary | Set similarity |
