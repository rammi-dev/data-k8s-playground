#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

GLUTEN_VERSION="1.7.0-SNAPSHOT"
SPARK_VERSION="4.0.0"
NIGHTLY_BASE="https://nightlies.apache.org/incubator/gluten/spark-4.0"

VELOX_JAR="gluten-velox-bundle-spark4.0_2.13-ubuntu_22.04_x86_64-${GLUTEN_VERSION}.jar"
CH_JAR="gluten-clickhouse-bundle-spark4.0_2.13-ubuntu_22.04_x86_64-${GLUTEN_VERSION}.jar"

# --- Download Velox bundle ---
if [[ ! -f "$VELOX_JAR" ]]; then
    echo "Downloading Velox bundle JAR..."
    wget -q --show-progress "${NIGHTLY_BASE}/${VELOX_JAR}" -O "$VELOX_JAR"
else
    echo "Velox bundle JAR already exists, skipping download"
fi

# --- Download ClickHouse bundle ---
if [[ ! -f "$CH_JAR" ]]; then
    echo "Downloading ClickHouse bundle JAR..."
    wget -q --show-progress "${NIGHTLY_BASE}/${CH_JAR}" -O "$CH_JAR"
else
    echo "ClickHouse bundle JAR already exists, skipping download"
fi

# --- Build Velox image ---
echo "Building spark-gluten-velox:${SPARK_VERSION}..."
docker build -f Dockerfile.velox -t "spark-gluten-velox:${SPARK_VERSION}" .

# --- Build ClickHouse image ---
echo "Building spark-gluten-ch:${SPARK_VERSION}..."
docker build -f Dockerfile.clickhouse -t "spark-gluten-ch:${SPARK_VERSION}" .

# --- Load into minikube ---
echo "Loading images into minikube..."
minikube image load "spark-gluten-velox:${SPARK_VERSION}"
minikube image load "spark-gluten-ch:${SPARK_VERSION}"

echo ""
echo "Images built and loaded:"
echo "  spark-gluten-velox:${SPARK_VERSION}"
echo "  spark-gluten-ch:${SPARK_VERSION}"
