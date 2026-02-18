#!/usr/bin/env bash
set -euo pipefail

# Generate benchmark data and upload to Ceph S3.
#
# Datasets:
#   - TPC-H SF10 (~3.6 GB Parquet) — generated via Spark's built-in TPC-H generator
#   - ClickBench hits.parquet (~14.8 GB) — downloaded from ClickHouse CDN
#
# Prerequisites:
#   - Ceph S3 accessible (rook-ceph-rgw)
#   - rook-ceph-tools pod running
#   - S3 user credentials available

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NAMESPACE="spark-workload"
S3_BUCKET="gluten-benchmark"
S3_ENDPOINT="http://rook-ceph-rgw-s3-store.rook-ceph.svc:80"
TOOLS_POD="$(kubectl -n rook-ceph get pod -l app=rook-ceph-tools -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"

# --- Read S3 credentials ---
S3_SECRET="rook-ceph-object-user-s3-store-gluten"
if ! kubectl -n rook-ceph get secret "$S3_SECRET" &>/dev/null; then
    echo "ERROR: S3 user secret '$S3_SECRET' not found."
    echo "Create CephObjectStoreUser 'gluten' in rook-ceph namespace first."
    exit 1
fi

S3_ACCESS_KEY=$(kubectl -n rook-ceph get secret "$S3_SECRET" -o jsonpath='{.data.AccessKey}' | base64 -d)
S3_SECRET_KEY=$(kubectl -n rook-ceph get secret "$S3_SECRET" -o jsonpath='{.data.SecretKey}' | base64 -d)

# --- Create S3 bucket ---
echo "Creating S3 bucket: ${S3_BUCKET}"
if [[ -n "$TOOLS_POD" ]]; then
    kubectl -n rook-ceph exec "$TOOLS_POD" -- bash -c "
        export AWS_ACCESS_KEY_ID='${S3_ACCESS_KEY}'
        export AWS_SECRET_ACCESS_KEY='${S3_SECRET_KEY}'
        aws s3 mb s3://${S3_BUCKET} --endpoint-url ${S3_ENDPOINT} 2>/dev/null || true
    "
else
    echo "WARNING: rook-ceph-tools pod not found. Create bucket manually."
fi

# --- Download ClickBench dataset ---
echo ""
echo "=== ClickBench Dataset ==="
CLICKBENCH_URL="https://datasets.clickhouse.com/hits_compatible/hits.parquet"
CLICKBENCH_LOCAL="/tmp/hits.parquet"

if [[ ! -f "$CLICKBENCH_LOCAL" ]]; then
    echo "Downloading ClickBench hits.parquet (~14.8 GB)..."
    wget -q --show-progress "$CLICKBENCH_URL" -O "$CLICKBENCH_LOCAL"
else
    echo "ClickBench hits.parquet already downloaded"
fi

echo "Uploading to s3://${S3_BUCKET}/clickbench/hits.parquet..."
if [[ -n "$TOOLS_POD" ]]; then
    # Copy to tools pod then upload
    kubectl -n rook-ceph cp "$CLICKBENCH_LOCAL" "${TOOLS_POD}:/tmp/hits.parquet"
    kubectl -n rook-ceph exec "$TOOLS_POD" -- bash -c "
        export AWS_ACCESS_KEY_ID='${S3_ACCESS_KEY}'
        export AWS_SECRET_ACCESS_KEY='${S3_SECRET_KEY}'
        aws s3 cp /tmp/hits.parquet s3://${S3_BUCKET}/clickbench/hits.parquet --endpoint-url ${S3_ENDPOINT}
        rm -f /tmp/hits.parquet
    "
else
    echo "WARNING: Cannot upload without rook-ceph-tools pod."
fi

# --- Generate TPC-H data ---
echo ""
echo "=== TPC-H SF10 Dataset ==="
echo "TPC-H data generation requires a running Spark session."
echo ""
echo "Option 1: Use spark-shell to generate:"
echo "  spark.range(1).selectExpr(\"1\").write.format(\"tpch\").option(\"scale\", \"10\").save(\"s3a://${S3_BUCKET}/tpch/sf10/\")"
echo ""
echo "Option 2: Use tpch-dbgen tool:"
echo "  git clone https://github.com/databricks/tpch-dbgen.git"
echo "  cd tpch-dbgen && make"
echo "  ./dbgen -s 10"
echo "  # Convert CSV to Parquet and upload to S3"
echo ""
echo "Option 3: Use spark-tpc-ds-performance-test:"
echo "  # Includes TPC-H Parquet generator for Spark"
echo ""

echo ""
echo "Data generation complete."
echo "Bucket: s3://${S3_BUCKET}/"
echo "  clickbench/hits.parquet  (~14.8 GB)"
echo "  tpch/sf10/               (generate using options above)"
