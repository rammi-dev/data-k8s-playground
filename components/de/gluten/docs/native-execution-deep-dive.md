# Native Execution Deep Dive

Why Gluten's native backends (Velox, ClickHouse) are faster than Spark's JVM execution.

## Table of Contents

- [Spark's Execution Model](#sparks-execution-model)
- [SIMD Vectorization](#simd-vectorization)
- [Off-Heap Memory and GC Elimination](#off-heap-memory-and-gc-elimination)
- [Native Parquet Decoding](#native-parquet-decoding)
- [Fallback Transitions](#fallback-transitions)
- [When Native Execution Doesn't Help](#when-native-execution-doesnt-help)

---

## Spark's Execution Model

Spark's structured processing engine (DataFrame API, Dataset API, and SQL) shares the same execution pipeline. All three compile down to identical Catalyst physical plans — the API is just a frontend, the execution is the same. Gluten intercepts at the physical plan level, so it accelerates DataFrame operations and SQL queries equally.

The engine has three execution modes — it is NOT naive row-at-a-time processing:

### 1. Volcano Model (Original)

Operators call `next()` one row at a time with virtual function dispatch per operator per row. Modern Spark rarely uses this for SQL queries.

### 2. Whole-Stage CodeGen (Spark 2.0+, Default)

Fuses multiple operators into a single generated Java method via the Janino compiler. No virtual dispatch between operators — tight loop over `UnsafeRow` byte arrays:

```java
// Generated code (simplified) — one fused method for Filter+Project+Agg
while (batch.hasNext()) {
    UnsafeRow row = batch.next();
    if (row.getInt(2) > 100) {           // filter
        sum += row.getDouble(5);          // project + aggregate
    }
}
```

The JIT compiler then optimizes this into efficient machine code.

### 3. Vectorized Parquet Reader

`VectorizedParquetRecordReader` reads data into `ColumnarBatch` (column vectors), but most operators still consume rows — Spark inserts an internal `ColumnarToRow` before processing.

### Gluten vs Spark CodeGen

The honest comparison is **JVM codegen vs native C++ vectorized execution** — not "slow row-by-row vs fast columnar." Spark's codegen is already good. Gluten's advantage comes from these areas:

| | Spark CodeGen | Gluten Native |
|---|---|---|
| Data layout | UnsafeRow (row-oriented byte arrays) | Arrow (columnar buffers) |
| SIMD | JVM auto-vectorization, opportunistic | Explicit SIMD intrinsics (AVX2/AVX-512) |
| Memory | JVM heap, subject to GC pauses | Off-heap `malloc`/`free`, no GC |
| Parquet decode | Java `parquet-mr`, byte-at-a-time | C++ DWio/CH native, SIMD + late materialization |
| Hashing | JVM murmur hash per row | Vectorized hash on column batches |

---

## SIMD Vectorization

### What SIMD Is

Modern CPUs have wide registers (256-bit AVX2, 512-bit AVX-512) that process multiple values in a single instruction:

```
Scalar (JVM):                SIMD (Velox/C++):
                             256-bit register
compare a[0] > 100          ┌────┬────┬────┬────┬────┬────┬────┬────┐
compare a[1] > 100          │a[0]│a[1]│a[2]│a[3]│a[4]│a[5]│a[6]│a[7]│  ← 8 ints loaded
compare a[2] > 100          └────┴────┴────┴────┴────┴────┴────┴────┘
compare a[3] > 100                   ONE instruction: cmpgt > 100
compare a[4] > 100          ┌────┬────┬────┬────┬────┬────┬────┬────┐
compare a[5] > 100          │ 1  │ 0  │ 1  │ 1  │ 0  │ 1  │ 0  │ 1  │  ← 8 results
compare a[6] > 100          └────┴────┴────┴────┴────┴────┴────┴────┘
compare a[7] > 100                       1 instruction
─────────────────
8 instructions
```

### Why JVM Can't Do This Well

The JVM has auto-vectorization — the JIT compiler can detect loops it might vectorize. But it's **opportunistic and often fails**:

- **UnsafeRow layout defeats it**: fields are at variable offsets within a byte array, so the JIT can't prove alignment or contiguity across rows
- **Columnar layout is SIMD-native**: `int32_column[0..7]` are contiguous in memory, perfect for `_mm256_loadu_si256`
- **No explicit intrinsics**: Java code can't call SIMD instructions directly (no `_mm256_cmpgt_epi32`). C++ code can, and Velox does extensively

### Where SIMD Matters Most

| Operation | Scalar (JVM) | SIMD (Native) | Speedup |
|-----------|-------------|---------------|---------|
| Filter evaluation (column > constant) | 1 compare/cycle | 8 compares/cycle (AVX2) | 4-8x |
| Hash computation (murmur3) | per-row hash | vectorized batch hash | 3-5x |
| Null bitmap operations | bit-at-a-time | bitwise AND/OR on 256 bits | 32-64x |
| Parquet decompression (Snappy) | byte-at-a-time | SIMD decode | 2-3x |
| Dictionary index lookup | `dict[idx]` per row | SIMD gather (`vpgatherdd`) | 4-8x |

---

## Off-Heap Memory and GC Elimination

### The JVM GC Problem

Garbage collection is the hidden tax on Spark. Even with `UnsafeRow` (which minimizes object count), Spark still allocates `byte[]` arrays on the JVM heap:

```
JVM Heap:
┌─────────────────────────────────────────────────────┐
│  Young Gen              │  Old Gen                   │
│  ┌───────────────────┐  │  ┌───────────────────────┐ │
│  │ UnsafeRow byte[]  │──┼─→│ promoted objects       │ │
│  │ hash map entries  │  │  │ shuffle buffers        │ │
│  │ temp objects      │  │  │ broadcast variables    │ │
│  └───────────────────┘  │  └───────────────────────┘ │
│    Minor GC: ~10ms      │   Major GC: 100ms - 5s     │
└─────────────────────────────────────────────────────┘
              ↑ stop-the-world pauses freeze ALL threads
```

A 10-million row shuffle creates 10 million `byte[]` arrays → GC pressure. On large hash joins with 100M+ rows, major GC pauses can reach **seconds**.

### JVM Object Overhead

Every Java object carries a header:

```
Java Integer object:          Native int32:
┌────────────────────┐        ┌──────┐
│ mark word (8 bytes)│        │ 4 B  │
│ klass ptr (8 bytes)│        └──────┘
│ value   (4 bytes)  │        = 4 bytes total
│ padding (4 bytes)  │
└────────────────────┘
= 24 bytes for a 4-byte value
```

UnsafeRow avoids this per-field, but the row byte arrays themselves are still JVM objects.

### Gluten's Memory Model

```
JVM Heap (small):                Off-Heap (native):
┌────────────────────────┐       ┌──────────────────────────────────┐
│ Spark metadata         │       │ Arrow buffers                    │
│ task scheduling        │ JNI   │ ┌──────────────────────────────┐ │
│ plan management        │←─────→│ │ int32 column:   40 MB        │ │
│ ~200 MB                │       │ │ string column:  120 MB       │ │
└────────────────────────┘       │ │ hash table:     500 MB       │ │
  GC: trivial, <1ms             │ │ shuffle buffer: 200 MB       │ │
                                 │ └──────────────────────────────┘ │
                                 │ malloc/free — deterministic       │
                                 │ no GC pauses, no stop-the-world  │
                                 │ 2-4 GB (spark.memory.offHeap.size)│
                                 └──────────────────────────────────┘
```

**Key differences:**

| | JVM Heap | Native Off-Heap |
|---|---|---|
| Allocation | `new byte[]` → GC-tracked | `malloc` → manual |
| Deallocation | GC (non-deterministic) | `free` (immediate) |
| Object overhead | 16 bytes/object header | 0 |
| Pauses | Stop-the-world GC (ms to seconds) | None |
| Memory reuse | GC reclaims eventually | Arena pools, immediate reuse |

**Velox memory pools**: Uses `MemoryPool` with arena allocation — pre-allocates large chunks, hands out sub-allocations, reuses buffers across batches instead of malloc/free per batch.

---

## Native Parquet Decoding

### Spark's Parquet Reader (`parquet-mr`, Java)

```
Parquet file on disk
    │
    ▼
Read page header (Java)
    │
    ▼
Decompress page (Java Snappy/Zstd)            ← byte-at-a-time
    │
    ▼
Decode repetition/definition levels (Java)     ← bit-unpacking loop
    │
    ▼
Decode values:
  - PLAIN:      memcpy
  - DICTIONARY: lookup[index] per value        ← one lookup at a time
  - DELTA:      reconstruct per value          ← sequential
    │
    ▼
Materialize ALL rows, ALL columns              ← eager materialization
into ColumnarBatch
    │
    ▼
ColumnarToRow (if needed by downstream operator)
```

### Velox's Parquet Reader (`DWio`, C++)

```
Parquet file on disk
    │
    ▼
Read page header (C++)
    │
    ▼
SIMD decompress (SIMD Snappy/Zstd)            ← 2-3x faster
    │
    ▼
SIMD bit-unpack rep/def levels                 ← 256 bits at once
    │
    ▼
Decode values:
  - PLAIN:      SIMD memcpy
  - DICTIONARY: SIMD gather instruction        ← 8 lookups in 1 instruction
  - DELTA:      SIMD prefix-sum                ← vectorized
    │
    ▼
Late materialization:                           ← KEY DIFFERENCE
  - Apply filter ON ENCODED data first
  - Only decode rows that pass the filter
  - Skip columns not in the projection
    │
    ▼
Arrow columnar buffer (zero-copy to downstream operators)
```

### Win #1: SIMD Decompression

Parquet pages are typically Snappy or Zstd compressed. Java implementations decompress byte-at-a-time. C++ implementations (used by Velox and ClickHouse) use SIMD-optimized routines:

- **Snappy**: Intel's optimized C++ implementation uses SSE4.2/AVX2 for literal copies and match decoding
- **Zstd**: Facebook's reference implementation has SIMD bitstream decoding

On compressed Parquet, decompression alone accounts for 20-40% of read time. SIMD gives 2-3x on this step.

### Win #2: Dictionary Fast Path

Parquet frequently dictionary-encodes string and low-cardinality columns. Consider filtering `WHERE country = 'US'`:

```
Spark (Java):
  For each row:
    1. Read dictionary index (e.g., 7)
    2. Look up dict[7] → "US"
    3. Compare string "US" == "US"
    4. If match, include row
  → N string comparisons

Velox (C++):
  1. Scan dictionary for "US" → found at index 7
  2. SIMD compare entire index column against constant 7:
     ┌───┬───┬───┬───┬───┬───┬───┬───┐
     │ 3 │ 7 │ 1 │ 7 │ 7 │ 2 │ 7 │ 0 │  indices
     └───┴───┴───┴───┴───┴───┴───┴───┘
              cmpgt == 7
     ┌───┬───┬───┬───┬───┬───┬───┬───┐
     │ 0 │ 1 │ 0 │ 1 │ 1 │ 0 │ 1 │ 0 │  result bitmap
     └───┴───┴───┴───┴───┴───┴───┴───┘
  → 1 dictionary lookup + N/8 SIMD integer comparisons
  → never touches the actual strings
```

For a column with 1 billion rows and 50 distinct countries, Spark does 1 billion string comparisons. Velox does 1 dictionary scan + ~125 million integer comparisons (8 at a time).

### Win #3: Late Materialization

This is the single biggest performance win for filter-heavy queries:

```
Query: SELECT name, amount FROM orders WHERE status = 'shipped'
Table: 100M rows, 20 columns, 10% pass filter

Spark (eager materialization):
  1. Read and decode ALL 20 columns for ALL 100M rows
  2. Apply filter → 10M rows pass
  3. Project name, amount from the 10M surviving rows
  4. Wasted work: decoded 90M × 20 columns for nothing
     Cost: decode 100M × 20 columns = 2 billion values

Velox (late materialization):
  1. Read and decode ONLY the status column (100M values)
  2. Apply filter → bitmap of 10M passing row positions
  3. Read and decode name, amount for ONLY those 10M rows
  4. Skipped: 90M rows × 19 columns never decoded
     Cost: decode 100M × 1 + 10M × 2 = 120M values
```

**Decode reduction: 2 billion → 120 million values (16x less work)**

The more selective the filter and the wider the table, the bigger the win:

| Filter Selectivity | Columns | Spark Decodes | Velox Decodes | Reduction |
|-------------------|---------|--------------|---------------|-----------|
| 10% pass | 20 | 100M × 20 | 100M × 1 + 10M × 19 | ~10x |
| 1% pass | 50 | 100M × 50 | 100M × 1 + 1M × 49 | ~50x |
| 50% pass | 5 | 100M × 5 | 100M × 1 + 50M × 4 | ~1.7x |

### ClickHouse vs Velox Parquet Reading

Both are native C++ but differ in architecture:

```
Velox (DWio):
  Parquet → DWio reader → Arrow columnar buffers (zero-copy)
  - Arrow-native, no conversion step
  - Late materialization built into reader
  - ~2-5x over Spark

ClickHouse:
  Parquet → CH native reader → CH column objects → Arrow conversion
  - Extra conversion step (CH columns → Arrow)
  - Strong predicate pushdown into reader
  - Better ORC support
  - ~1.5-3x over Spark
```

---

## Fallback Transitions

### UnsafeRow

Spark's internal row format. Packs an entire row into a contiguous byte array with fixed-width offsets — avoids creating a Java object per field:

```
┌───────────┬───────────┬───────────┬────────────────────┐
│ null bits  │ field 1   │ field 2   │ variable-length    │
│ (bitmap)   │ (8 bytes) │ (8 bytes) │ (strings, etc.)    │
└───────────┴───────────┴───────────┴────────────────────┘
              one contiguous byte[] allocation
```

- Fixed-width types (int, long, double): stored inline at known offsets
- Variable-width types (string, binary): stored at the end, referenced by offset + length
- Direct memory access via `sun.misc.Unsafe` (hence the name)

### ColumnarToRow and RowToColumnar

When Gluten encounters an operator it can't execute natively (a fallback), it must convert between formats:

```
ColumnarToRow:                              RowToColumnar:
Arrow columnar → UnsafeRow                  UnsafeRow → Arrow columnar

Column 1: [1, 2, 3, 4, 5]                  Row 1: [1|"alice"|3.14]
Column 2: ["alice","bob","carol"...]  →     Row 2: [2|"bob"  |2.71]  →  Column vectors
Column 3: [3.14, 2.71, 1.41...]            Row 3: [3|"carol"|1.41]

(transpose: column-oriented → row-oriented) (transpose: row-oriented → column-oriented)
```

### Cost of Fallback Transitions

Each fallback operator in the plan creates **two** transposes:

```
NativeScanExec (columnar)
    ↓
NativeFilterExec (columnar)
    ↓
  ColumnarToRow  ← transpose: columns → UnsafeRow
    ↓
JVM operator (fallback)
    ↓
  RowToColumnar  ← transpose: UnsafeRow → columns
    ↓
NativeHashAggExec (columnar)
```

Multiple non-consecutive fallbacks multiply the cost:

```
Native → C2R → JVM fallback → R2C → Native → C2R → JVM fallback → R2C → Native
         ^^^                   ^^^            ^^^                   ^^^
                    4 transposes = real overhead
```

Each transpose is O(rows × columns) memory operations. On a 10-million row dataset with 20 columns, each transition touches every value.

### Inspecting Transitions

Check the physical plan for `ColumnarToRow` and `RowToColumnar` nodes:

```sql
spark.sql("EXPLAIN EXTENDED SELECT ...").show(truncate=false)
```

If you see these transitions in a hot path (inside a join or tight loop), that's where performance leaks. Ideally a plan has native operators end-to-end with a single `ColumnarToRow` only at the final output or write stage.

---

## When Native Execution Doesn't Help

| Scenario | Why |
|----------|-----|
| Python UDFs | Executed in Python subprocess, data serialized via Arrow IPC regardless |
| JDBC / CSV / JSON sources | Java-only readers, no native path |
| Very small datasets (< 10K rows) | JNI overhead and batch setup cost outweigh gains |
| Write-dominated pipelines | Iceberg/Parquet writers are JVM-only, `ColumnarToRow` transition required |
| Single-row lookups | SIMD needs batches to amortize; single-row = no vectorization benefit |
| GPU workloads (RAPIDS) | Different acceleration path, Gluten targets CPU only |
