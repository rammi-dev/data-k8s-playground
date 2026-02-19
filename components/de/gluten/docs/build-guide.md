# Building Spark with Gluten

## Overview

Gluten ships as a single "uber JAR" (bundle) per backend. Drop it into Spark's `jars/` directory — no changes to Spark source code required.

Two approaches:
- **Option A**: Pre-built nightly JARs for Spark 4.0.0 (fastest)
- **Option B**: Build from source for Spark 4.1.1 (matches playground version)

## Option A: Pre-Built Nightly JARs (Spark 4.0.0)

### Download JARs

Gluten nightly builds are published by the Apache CI. The bundle JARs contain the native backend library (`.so`) and all Java/Scala glue code.

```bash
# Velox backend bundle
# Check https://nightlies.apache.org/incubator/gluten/ for latest nightly
wget https://nightlies.apache.org/incubator/gluten/spark-4.0/gluten-velox-bundle-spark4.0_2.13-ubuntu_22.04_x86_64-1.7.0-SNAPSHOT.jar

# ClickHouse backend bundle
wget https://nightlies.apache.org/incubator/gluten/spark-4.0/gluten-clickhouse-bundle-spark4.0_2.13-ubuntu_22.04_x86_64-1.7.0-SNAPSHOT.jar
```

Bundle JARs are ~200 MB (Velox) or ~500 MB (ClickHouse) — they embed the entire native library.

### Build Docker Images

```dockerfile
# Dockerfile.velox
FROM apache/spark:4.0.0
USER root
COPY gluten-velox-bundle-spark4.0_2.13-*.jar /opt/spark/jars/
USER spark
```

```dockerfile
# Dockerfile.clickhouse
FROM apache/spark:4.0.0
USER root
COPY gluten-clickhouse-bundle-spark4.0_2.13-*.jar /opt/spark/jars/
USER spark
```

```bash
docker build -f docker/Dockerfile.velox -t spark-gluten-velox:4.0.0 docker/
docker build -f docker/Dockerfile.clickhouse -t spark-gluten-ch:4.0.0 docker/
```

### Load into Minikube

```bash
minikube image load spark-gluten-velox:4.0.0
minikube image load spark-gluten-ch:4.0.0
```

## Option B: Build from Source

Gluten has **no `-Pspark-4.1` profile** yet. The highest supported profile is `-Pspark-4.0`, which compiles against Spark 4.0.0 internal APIs (`catalyst`, `sql.execution`).

> **Spark 4.1.1 does NOT work.** Overriding `-Dspark.version=4.1.1` fails — Spark 4.1 changed internal APIs that Gluten's `shims/spark40/` layer depends on (`StoragePartitionJoinParams` removed, `createSparkPlan`/`readFooter` signatures changed, `GenerateTreeStringShim` Int→Boolean). A new `shims/spark41/` module is needed upstream. Use **Spark 4.0.0** for all Gluten builds.


Use `-Pspark-4.0` as-is. The Gluten JAR is compiled against Spark 4.0.0 APIs but loaded into a Spark 4.0.0 runtime — fully compatible. For benchmarking, the execution engine differences between 4.0 and 4.1 are negligible compared to the JVM→native speedup.

### Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| JDK | 17 | Java compilation |
| Maven | 3.9+ | Build system |
| CMake | 3.20+ | Native build |
| Ninja | 1.10+ | Parallel native build |
| GCC | 12+ | C++ compilation (C++17 required) |
| Git | 2.x | Source checkout |

On Ubuntu 22.04:

```bash
sudo apt install -y openjdk-17-jdk maven cmake ninja-build gcc-12 g++-12 git
sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-12 100
sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-12 100
```

### Build Steps

```bash
# Clone
git clone https://github.com/apache/incubator-gluten.git
cd incubator-gluten
git checkout main

# Build Velox backend (compiles against Spark 4.0.0)
mvn clean package -Pspark-4.0 -Pscala-2.13 -Pbackends-velox -DskipTests \
    -Dmaven.javadoc.skip=true -Dcheckstyle.skip=true
# Output: backends-velox/target/gluten-velox-bundle-spark4.0_2.13-*.jar

# Build ClickHouse backend (separate build, compiles against Spark 4.0.0)
# NOTE: ClickHouse backend requires -Pdelta profile
mvn clean package -Pspark-4.0 -Pscala-2.13 -Pbackends-clickhouse -Pdelta -DskipTests \
    -Dmaven.javadoc.skip=true -Dcheckstyle.skip=true
# Output: backends-clickhouse/target/gluten-clickhouse-bundle-spark4.0_2.13-*.jar

# NOTE: -Dspark.version=4.1.1 override does NOT work (confirmed).
# Spark 4.1 removed StoragePartitionJoinParams, changed createSparkPlan/readFooter
# signatures, and GenerateTreeStringShim Int→Boolean. Wait for upstream shims/spark41.
```

Build time: ~30-60 minutes depending on hardware. The native portion (Velox/ClickHouse compilation) takes the majority of time.

### Multi-Stage Dockerfile (Build from Source)

```dockerfile
# Stage 1: Build
FROM ubuntu:22.04 AS builder
RUN apt-get update && apt-get install -y \
    openjdk-17-jdk maven cmake ninja-build gcc-12 g++-12 git curl
ENV JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64

WORKDIR /build
RUN git clone --depth 1 https://github.com/apache/incubator-gluten.git
WORKDIR /build/incubator-gluten
RUN mvn clean package -Pspark-4.0 -Pscala-2.13 -Pbackends-velox -DskipTests \
    -Dmaven.javadoc.skip=true -Dcheckstyle.skip=true

# Stage 2: Runtime (must match the Spark version Gluten was compiled against)
FROM apache/spark:4.0.0
USER root
COPY --from=builder /build/incubator-gluten/backends-velox/target/gluten-velox-bundle-*.jar /opt/spark/jars/
USER spark
```

## Spark Configuration for Gluten

### Velox Backend

```yaml
sparkConf:
  # Gluten plugin
  spark.plugins: "org.apache.gluten.GlutenPlugin"
  spark.shuffle.manager: "org.apache.spark.shuffle.sort.ColumnarShuffleManager"
  spark.gluten.sql.columnar.backend.lib: "velox"

  # Off-heap memory (required)
  spark.memory.offHeap.enabled: "true"
  spark.memory.offHeap.size: "2g"

  # Optional: Velox tuning
  spark.gluten.sql.columnar.maxBatchSize: "4096"
  spark.gluten.sql.columnar.forceShuffledHashJoin: "true"
```

### ClickHouse Backend

```yaml
sparkConf:
  # Gluten plugin
  spark.plugins: "org.apache.gluten.GlutenPlugin"
  spark.shuffle.manager: "org.apache.spark.shuffle.sort.ColumnarShuffleManager"
  spark.gluten.sql.columnar.backend.lib: "clickhouse"

  # Off-heap memory (required)
  spark.memory.offHeap.enabled: "true"
  spark.memory.offHeap.size: "2g"

  # Optional: ClickHouse tuning
  spark.gluten.sql.columnar.maxBatchSize: "4096"
  spark.gluten.sql.columnar.backend.ch.runtime_config.use_local_format: "true"
```

### S3 Access (Ceph RGW)

Both backends need S3 configuration for reading data from Ceph:

```yaml
sparkConf:
  spark.hadoop.fs.s3a.endpoint: "http://rook-ceph-rgw-s3-store.rook-ceph.svc:80"
  spark.hadoop.fs.s3a.access.key: "<from-secret>"
  spark.hadoop.fs.s3a.secret.key: "<from-secret>"
  spark.hadoop.fs.s3a.path.style.access: "true"
  spark.hadoop.fs.s3a.impl: "org.apache.hadoop.fs.s3a.S3AFileSystem"
  spark.hadoop.fs.s3a.connection.ssl.enabled: "false"
```

## Verifying Gluten is Active

After submitting a SparkApplication, check driver logs:

```bash
# Check plugin loaded
kubectl logs <driver-pod> -n spark-workload | grep -i "gluten"

# Expected output:
# GlutenPlugin loaded with backend: velox (or clickhouse)
# ColumnarShuffleManager registered

# Check operator replacement in query plan
# In Spark UI (port 4040), check SQL tab → query plan
# Native operators show as "NativeScanExec", "NativeFilterExec", etc.
# JVM fallbacks show as standard "FilterExec", "ProjectExec", etc.
```
