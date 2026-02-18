# Apache Gluten

Native execution engine comparison for Spark. Benchmarks Spark with Velox backend, ClickHouse backend, and native JVM execution on identical workloads.

| Property | Value |
|----------|-------|
| Gluten | 1.7.0-SNAPSHOT (nightly) |
| Spark | 4.0.0 |
| Backends | Velox (Meta), ClickHouse |
| Datasets | TPC-H SF10, ClickBench |

## Prerequisites

- Spark Operator deployed (`components/spark/apache`)
- Ceph S3 accessible (`rook-ceph-rgw-s3-store.rook-ceph.svc:80`)
- `spark` ServiceAccount in `spark-workload` namespace

## Usage

```bash
# Build Docker images (downloads Gluten JARs, builds two images)
./docker/build-images.sh

# Generate test data on Ceph S3
./scripts/generate-data.sh

# Run benchmark (all 3 engines, prints comparison table)
./scripts/benchmark.sh

# Run individual engines
kubectl apply -f manifests/spark-app-baseline.yaml
kubectl apply -f manifests/spark-app-velox.yaml
kubectl apply -f manifests/spark-app-clickhouse.yaml
```

## Docs

| Document | Content |
|----------|---------|
| [Architecture](docs/architecture.md) | Gluten internals, operator replacement, join strategies, memory model, Mermaid diagrams |
| [Benchmark Plan](docs/benchmark-plan.md) | Datasets, queries, test matrix, expected results |
| [Build Guide](docs/build-guide.md) | Docker image build (pre-built JARs or from source), Spark configuration |

## File Structure

```
gluten/
├── README.md
├── docs/
│   ├── architecture.md
│   ├── benchmark-plan.md
│   └── build-guide.md
├── docker/
│   ├── Dockerfile.velox
│   ├── Dockerfile.clickhouse
│   └── build-images.sh
├── manifests/
│   ├── spark-app-baseline.yaml
│   ├── spark-app-velox.yaml
│   └── spark-app-clickhouse.yaml
└── scripts/
    ├── benchmark.sh
    └── generate-data.sh
```
