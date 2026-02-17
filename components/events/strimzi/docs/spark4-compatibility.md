# Spark 4 — Connect vs Classic Compatibility

## Two Execution Modes

Spark 4 ships with two execution modes in a single codebase:

```
Classic (default)                    Connect (client-server)
┌─────────────────────┐              ┌──────────┐     gRPC     ┌──────────────┐
│  Driver JVM         │              │  Client   │ ──────────→ │  Spark Server│
│  ┌───────────────┐  │              │  (thin)   │             │  (cluster)   │
│  │ Your code     │  │              │  1.5 MB   │             │              │
│  │ SparkSession  │  │              └──────────┘             └──────────────┘
│  │ Executors     │  │
│  └───────────────┘  │              Client languages:
└─────────────────────┘              Python, Scala, Java, Go, Rust, Swift
```

| Aspect | Classic | Connect |
|--------|---------|---------|
| Architecture | Monolithic — code runs in driver JVM | Client-server — thin client over gRPC |
| APIs available | RDD + DataFrame + SQL | DataFrame + SQL only (**no RDD**) |
| Driver access | Direct JVM access | No access to driver JVM |
| Crash isolation | Client crash can kill driver | Client crash doesn't affect server |
| Remote access | Limited (JDBC/ODBC) | Full remote connectivity |
| Package size | Full Spark (~300 MB) | `pyspark-client` (~1.5 MB) |

**Switch between modes at runtime:**

```python
from pyspark.sql import SparkSession

# Classic mode (default)
spark = SparkSession.builder \
    .config("spark.api.mode", "classic") \
    .getOrCreate()

# Connect mode
spark = SparkSession.builder \
    .config("spark.api.mode", "connect") \
    .master("spark://spark-master:7077") \
    .getOrCreate()
```

```bash
# Via spark-submit
spark-submit --conf spark.api.mode=connect --master spark://spark-master:7077 app.py
```

## Behavior Differences (Connect vs Classic)

These are the differences that will silently break your code — same API, different behavior.

### 1. Schema Analysis: Eager vs Lazy

**Classic** analyzes immediately. **Connect** defers analysis to execution.

```python
df = spark.sql("SELECT 1 AS a, 2 AS b").filter("nonexistent_col > 1")

# Classic: AnalysisException thrown HERE, immediately
# Connect: No error — unresolved plan stays on client

df.show()
# Classic: already failed above
# Connect: AnalysisException thrown HERE, at execution time
```

**Impact:** Error detection is delayed in Connect mode. Code that catches exceptions around transformations won't work.

**Fix:** Trigger eager analysis explicitly when you need early error detection:

```python
try:
    df = spark.sql("SELECT 1 AS a").filter("bad_col > 1")
    df.columns  # Forces analysis → throws error in Connect mode too
except Exception as e:
    print(f"Caught: {e}")
```

| Operation | Classic | Connect |
|-----------|---------|---------|
| `df.filter(...)`, `df.select(...)` | Eager analysis | Lazy (no analysis) |
| `df.columns`, `df.schema` | Eager (local) | Triggers RPC to server |
| `df.show()`, `df.collect()` | Eager | Eager |
| UDF registration | Eager serialization | Lazy (serialized at execution) |
| `createOrReplaceTempView()` | Plan embedded in DataFrame | Name reference only |

### 2. Temporary Views: Embedded vs Referenced

```python
# Classic: view plan is EMBEDDED in df at creation time
spark.range(10).createOrReplaceTempView("my_view")
df = spark.table("my_view")   # df captures the plan (range(10))

spark.range(100).createOrReplaceTempView("my_view")  # replace view
df.count()
# Classic: returns 10 (original plan embedded)
# Connect: returns 100 (looks up "my_view" by name at execution)
```

**Impact:** Code that reuses temp view names will get different data in Connect mode.

**Fix:** Use unique view names (include UUID):

```python
import uuid

def safe_temp_view(df, prefix="view"):
    name = f"`{prefix}_{uuid.uuid4()}`"
    df.createOrReplaceTempView(name)
    return spark.table(name)
```

### 3. UDF Serialization: Eager vs Lazy

```python
from pyspark.sql.functions import udf

x = 123

@udf("INT")
def get_value():
    return x

df = spark.range(1).select(get_value())
x = 456

df.show()
# Classic: prints 123 (x captured at UDF creation)
# Connect: prints 456 (UDF serialized at execution, captures current x)
```

**Fix:** Wrap UDFs in factory functions to capture values at creation time:

```python
def make_udf(value):
    @udf("INT")
    def get_value():
        return value
    return get_value

x = 123
my_udf = make_udf(x)  # value captured here
x = 456
spark.range(1).select(my_udf()).show()  # prints 123 in both modes
```

### 4. Schema Access Performance

In Connect mode, every `df.columns` or `df.schema` call triggers an RPC to the server. In Classic mode, it's a local operation.

```python
# BAD in Connect mode — 200 RPC calls
df = spark.range(10)
for i in range(200):
    if str(i) not in df.columns:  # RPC every iteration!
        df = df.withColumn(str(i), col("id") + i)

# GOOD — one RPC, then local set lookups
df = spark.range(10)
columns = set(df.columns)  # one RPC
for i in range(200):
    name = str(i)
    if name not in columns:  # local lookup
        df = df.withColumn(name, col("id") + i)
        columns.add(name)
```

### 5. No RDD Access in Connect Mode

```python
# Classic: works
rdd = spark.sparkContext.parallelize([1, 2, 3])
df = spark.createDataFrame(rdd.map(lambda x: (x,)), ["value"])

# Connect: SparkContext not available
# spark.sparkContext → AttributeError
```

**Fix:** Use DataFrame API exclusively:

```python
# Works in both modes
df = spark.createDataFrame([(1,), (2,), (3,)], ["value"])
```

## Spark 4.0 Breaking Changes (Both Modes)

These changes affect **all** Spark 4 code regardless of Connect vs Classic.

### ANSI Mode Enabled by Default

The single biggest breaking change. `spark.sql.ansi.enabled` is now `true` by default.

```sql
-- Spark 3.x (ANSI off): silent overflow, returns NULL or wrong value
SELECT CAST('abc' AS INT);          -- Returns NULL
SELECT 2147483647 + 1;              -- Returns -2147483648 (overflow wraps)

-- Spark 4.0 (ANSI on): throws exceptions
SELECT CAST('abc' AS INT);          -- CAST_INVALID_INPUT error
SELECT 2147483647 + 1;              -- ARITHMETIC_OVERFLOW error
```

**Impact:** Queries that relied on silent failures now throw exceptions.

**Fix:** Set `spark.sql.ansi.enabled=false` for backward compatibility, or fix the queries:

```sql
-- Safe casting (returns NULL instead of error)
SELECT TRY_CAST('abc' AS INT);          -- Returns NULL
SELECT TRY_ADD(2147483647, 1);          -- Returns NULL
```

### Default Table Provider Changed

```sql
-- Spark 3.x: creates Hive SerDe table
CREATE TABLE my_table (id INT, name STRING);

-- Spark 4.0: creates Parquet table (uses spark.sql.sources.default)
CREATE TABLE my_table (id INT, name STRING);
```

**Fix:** `spark.sql.legacy.createHiveTableByDefault=true` or explicitly specify `USING HIVE`.

### ORC Compression Default Changed

```
Spark 3.x: spark.sql.orc.compression.codec = snappy
Spark 4.0: spark.sql.orc.compression.codec = zstd
```

Existing ORC files are unaffected (codec is per-file), but new files will use zstd. Set to `snappy` if downstream tools can't read zstd.

### Bang Operator (!) Removed as NOT Prefix

```sql
-- Spark 3.x: accepted
WHERE col ! IN (1, 2, 3)
WHERE col ! BETWEEN 1 AND 10

-- Spark 4.0: syntax error
WHERE col NOT IN (1, 2, 3)
WHERE col NOT BETWEEN 1 AND 10
```

### CTE Precedence Changed

```sql
WITH t AS (SELECT 1 AS x),
     t2 AS (WITH t AS (SELECT 2 AS x) SELECT * FROM t)
SELECT * FROM t2;

-- Spark 3.x (EXCEPTION mode): raised error on name conflict
-- Spark 4.0 (CORRECTED mode): returns 2 (inner CTE wins)
```

### Map Key Normalization

```python
# Spark 3.x: -0.0 and 0.0 are different map keys
# Spark 4.0: -0.0 is normalized to 0.0

from pyspark.sql.functions import create_map, lit
df = spark.range(1).select(create_map(lit(-0.0), lit("neg"), lit(0.0), lit("pos")))
# Spark 4.0: only one key (0.0) — last value wins
```

### Storage-Partitioned Join Enabled by Default

Spark 4.0 enables storage-partitioned joins (`spark.sql.sources.v2.bucketing.pushPartValues.enabled=true`). This means bucketed/partitioned V2 tables (like **Iceberg**) can skip shuffle entirely when join keys align with partition keys.

**This is good** — but if your code assumed shuffle behavior or partition counts, results may differ.

## JDBC Type Mapping Changes

These affect any code reading from or writing to databases:

| Database | Column Type | Spark 3.x Type | Spark 4.0 Type |
|----------|-----------|----------------|----------------|
| **MySQL** | `SMALLINT` | `IntegerType` | `ShortType` |
| **MySQL** | `FLOAT` | `DoubleType` | `FloatType` |
| **MySQL** | `BIT(n>1)` | `LongType` | `BinaryType` |
| **MySQL** | `TIMESTAMP` | Depends on `preferTimestampNTZ` | Always `TimestampType` |
| **PostgreSQL** | `TIMESTAMP WITH TZ` | Depends on `preferTimestampNTZ` | Always `TimestampType` |
| **MS SQL** | `TINYINT` | `IntegerType` | `ShortType` |
| **MS SQL** | `DATETIMEOFFSET` | `StringType` | `TimestampType` |
| **DB2** | `SMALLINT` | `IntegerType` | `ShortType` |
| **Oracle** | `TimestampType` write | `TIMESTAMP` | `TIMESTAMP WITH LOCAL TZ` |

**Fix:** Use `spark.sql.legacy.<db>.<feature>.enabled=true` configs per database. See migration guide for exact config names.

## PySpark-Specific Changes

### Minimum Dependency Versions

| Dependency | Spark 3.5 | Spark 4.0 |
|-----------|-----------|-----------|
| **Python** | 3.8+ | **3.9+** |
| **Pandas** | 1.0.5+ | **2.0.0+** |
| **NumPy** | 1.15+ | **1.21+** |
| **PyArrow** | 4.0.0+ | **11.0.0+** |

### Removed pandas API Methods

```python
# Removed — use replacements
df.iteritems()    → df.items()
df.append(other)  → ps.concat([df, other])
df.mad()          → removed, no replacement
Int64Index(...)   → ps.Index(...)
Float64Index(...) → ps.Index(...)
```

### pandas API on Spark + ANSI Mode

Since ANSI mode is on by default, pandas API on Spark raises exceptions where it previously returned NULL:

```python
import pyspark.pandas as ps

ps.set_option("compute.fail_on_ansi_mode", False)  # suppress ANSI errors
# OR
spark.conf.set("spark.sql.ansi.enabled", "false")    # disable ANSI globally
```

### Schema Inference Changed

```python
# Spark 3.x: map schema inferred from FIRST non-null pair
# Spark 4.0: map schema MERGED from ALL pairs

data = [{"a": {"key1": 1}}, {"a": {"key2": "text"}}]
df = spark.createDataFrame(data)
# Spark 3.x: MapType(StringType, IntegerType)
# Spark 4.0: MapType(StringType, StringType) — merged from all pairs
```

**Fix:** `spark.sql.pyspark.legacy.inferMapTypeFromFirstPair.enabled=true`

### Wildcard Import Changed

```python
# Spark 3.x: imported types + DataFrame + Column
from pyspark.sql.functions import *  # included DataFrame, Column, etc.

# Spark 4.0: only functions
from pyspark.sql.functions import *  # DataFrame, Column NOT included
from pyspark.sql import DataFrame, Column  # import separately
```

## Structured Streaming Changes

### Streaming-Specific Breaking Changes

| Change | Spark 3.x | Spark 4.0 |
|--------|-----------|-----------|
| `Trigger.AvailableNow` | Works even if source doesn't support it | Falls back to single batch if source unsupported |
| Checkpoint space | No limit on stale files | `ratioExtraSpaceAllowedInCheckpoint=0.3` (30% overhead) |
| Relative paths in `DataStreamWriter` | Resolved on executor | Resolved on driver (consistent with batch) |
| AQE for stateless streaming (4.1) | Disabled | Enabled by default |

### State Management Migration

```
Spark 3.x API (deprecated)          →  Spark 4.0 API
─────────────────────────────       ──────────────────────────
mapGroupsWithState                  →  transformWithState
flatMapGroupsWithState              →  transformWithState
applyInPandasWithState (Python)     →  transformWithStateInPandas
Single opaque state object          →  Multiple typed: ValueState, ListState, MapState
Manual state cleanup                →  Native TTL per state variable
No timer support                    →  Processing-time + event-time timers
No state inspection                 →  State Data Source (read state as DataFrame)
```

The old APIs still work in 4.0 but are not recommended for new code. `transformWithState` is the future.

## Spark Core Changes

| Change | Spark 3.x | Spark 4.0 |
|--------|-----------|-----------|
| **Mesos** | Supported | **Removed** |
| **Servlet API** | `javax.servlet` | `jakarta.servlet` (breaks custom UIs) |
| **Shuffle DB** | LevelDB | RocksDB |
| **K8s PVC access** | `ReadWriteOnce` | `ReadWriteOncePod` |
| **Event log rolling** | Off | On |
| **Event log compression** | Off | On |
| **Speculative execution** | Aggressive (1.5x, 75th pctile) | Conservative (3x, 90th pctile) |
| **Ivy directory** | `~/.ivy2` | `~/.ivy2.5.2` (isolation) |

## Migration Checklist

```
Phase 1: Assess (before upgrading)
□ Search for RDD usage — must convert to DataFrame API for Connect mode
□ Search for ! operator in SQL — replace with NOT
□ Check Python version ≥ 3.9, pandas ≥ 2.0, numpy ≥ 1.21, pyarrow ≥ 11.0
□ Check Hive metastore version ≥ 2.0.0
□ List all JDBC sources — review type mapping changes per database
□ Check for javax.servlet usage in custom extensions

Phase 2: Configure (set legacy flags first)
□ spark.sql.ansi.enabled=false                              # if not ready for ANSI
□ spark.sql.legacy.createHiveTableByDefault=true            # if using Hive tables
□ spark.sql.orc.compression.codec=snappy                    # if downstream needs snappy
□ spark.sql.legacy.bangEqualsNot=true                       # if using ! syntax
□ spark.sql.legacy.<db>.*.enabled=true                      # per JDBC database

Phase 3: Test
□ Run full test suite with Spark 4.0 + Classic mode
□ Test ANSI mode: re-run with spark.sql.ansi.enabled=true
  □ Fix overflow/cast errors with TRY_CAST, TRY_ADD
□ Test Connect mode: spark.api.mode=connect
  □ Verify temp view behavior
  □ Verify UDF capture behavior
  □ Verify error handling timing

Phase 4: Adopt
□ Remove legacy flags one by one
□ Migrate mapGroupsWithState → transformWithState
□ Move to Connect mode for new applications
□ Use pyspark-client (1.5 MB) for lightweight deployments
```

## Connect vs Classic Decision

```
Are you building a new application?
  └── YES → Use Connect (lighter, safer, future-proof)
  └── NO ↓

Does your code use RDDs?
  └── YES → Stay on Classic (refactor RDDs → DataFrames first)
  └── NO ↓

Does your code rely on eager schema analysis for error handling?
  └── YES → Stay on Classic (or add explicit .columns calls)
  └── NO ↓

Does your code reuse temp view names?
  └── YES → Fix first (use unique names), then Connect
  └── NO → Safe to switch to Connect
```

## References

- [Spark 4.0 Release Notes](https://spark.apache.org/releases/spark-release-4-0-0.html)
- [SQL Migration Guide](https://spark.apache.org/docs/4.0.0/sql-migration-guide.html)
- [Core Migration Guide](https://spark.apache.org/docs/latest/core-migration-guide.html)
- [PySpark Migration Guide](https://github.com/apache/spark/blob/master/python/docs/source/migration_guide/pyspark_upgrade.rst)
- [Streaming Migration Guide](https://spark.apache.org/docs/latest/streaming/ss-migration-guide.html)
- [Spark Connect Application Development](https://spark.apache.org/docs/4.0.0/app-dev-spark-connect.html)
- [Connect vs Classic (Databricks)](https://learn.microsoft.com/en-us/azure/databricks/spark/connect-vs-classic)
