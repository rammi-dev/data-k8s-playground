#!/usr/bin/env bash
set -euo pipefail

# Run Gluten benchmark: baseline vs Velox vs ClickHouse.
#
# Submits three SparkApplications sequentially, waits for completion,
# extracts timing from driver logs, and prints comparison table.
#
# Prerequisites:
#   - Docker images built (./docker/build-images.sh)
#   - Test data on Ceph S3 (./scripts/generate-data.sh)
#   - Spark Operator running

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MANIFEST_DIR="${SCRIPT_DIR}/../manifests"
NAMESPACE="spark-workload"

# SparkApplication names (must match metadata.name in manifests)
APPS=("spark-baseline" "spark-gluten-velox" "spark-gluten-ch")
MANIFESTS=("spark-app-baseline.yaml" "spark-app-velox.yaml" "spark-app-clickhouse.yaml")
LABELS=("Native Spark" "Gluten/Velox" "Gluten/ClickHouse")

TIMEOUT=600  # 10 minutes per app

# --- Inject S3 credentials into manifests ---
S3_SECRET="rook-ceph-object-user-s3-store-gluten"
if kubectl -n rook-ceph get secret "$S3_SECRET" &>/dev/null; then
    S3_ACCESS_KEY=$(kubectl -n rook-ceph get secret "$S3_SECRET" -o jsonpath='{.data.AccessKey}' | base64 -d)
    S3_SECRET_KEY=$(kubectl -n rook-ceph get secret "$S3_SECRET" -o jsonpath='{.data.SecretKey}' | base64 -d)
else
    echo "ERROR: S3 user secret '$S3_SECRET' not found."
    exit 1
fi

wait_for_completion() {
    local app_name="$1"
    local elapsed=0

    while [[ $elapsed -lt $TIMEOUT ]]; do
        state=$(kubectl get sparkapplication "$app_name" -n "$NAMESPACE" -o jsonpath='{.status.applicationState.state}' 2>/dev/null || echo "PENDING")

        case "$state" in
            COMPLETED)
                return 0
                ;;
            FAILED|SUBMISSION_FAILED)
                echo "  FAILED: $app_name"
                return 1
                ;;
        esac

        sleep 5
        elapsed=$((elapsed + 5))
    done

    echo "  TIMEOUT: $app_name (${TIMEOUT}s)"
    return 1
}

get_duration() {
    local app_name="$1"
    local driver_pod="${app_name}-driver"

    # Extract total execution time from driver logs
    # Look for "Benchmark completed in X seconds" or calculate from timestamps
    local duration
    duration=$(kubectl logs "$driver_pod" -n "$NAMESPACE" 2>/dev/null | \
        grep -oP 'completed in \K[0-9.]+(?= seconds)' | tail -1 || echo "N/A")

    if [[ "$duration" == "N/A" ]]; then
        # Fallback: calculate from pod start to completion
        local start end
        start=$(kubectl get pod "$driver_pod" -n "$NAMESPACE" -o jsonpath='{.status.startTime}' 2>/dev/null || echo "")
        end=$(kubectl get pod "$driver_pod" -n "$NAMESPACE" -o jsonpath='{.status.containerStatuses[0].state.terminated.finishedAt}' 2>/dev/null || echo "")

        if [[ -n "$start" && -n "$end" ]]; then
            local start_epoch end_epoch
            start_epoch=$(date -d "$start" +%s 2>/dev/null || echo 0)
            end_epoch=$(date -d "$end" +%s 2>/dev/null || echo 0)
            if [[ $start_epoch -gt 0 && $end_epoch -gt 0 ]]; then
                duration=$(( end_epoch - start_epoch ))
            fi
        fi
    fi

    echo "$duration"
}

# --- Run benchmarks ---
echo "============================================"
echo "  Gluten Benchmark: 3-Way Comparison"
echo "============================================"
echo ""

declare -a DURATIONS

for i in "${!APPS[@]}"; do
    app="${APPS[$i]}"
    manifest="${MANIFESTS[$i]}"
    label="${LABELS[$i]}"

    echo "--- ${label} ---"

    # Clean up previous run
    kubectl delete sparkapplication "$app" -n "$NAMESPACE" 2>/dev/null || true
    sleep 2

    # Submit with S3 credentials
    # TODO: patch manifest with credentials or use env injection
    echo "  Submitting ${manifest}..."
    kubectl apply -f "${MANIFEST_DIR}/${manifest}"

    echo "  Waiting for completion (timeout: ${TIMEOUT}s)..."
    if wait_for_completion "$app"; then
        duration=$(get_duration "$app")
        DURATIONS[$i]="$duration"
        echo "  Duration: ${duration}s"
    else
        DURATIONS[$i]="FAILED"
    fi

    echo ""
done

# --- Print comparison table ---
echo "============================================"
echo "  Results"
echo "============================================"
echo ""
printf "%-20s | %10s | %10s\n" "Engine" "Duration" "Speedup"
printf "%-20s-+-%10s-+-%10s\n" "--------------------" "----------" "----------"

baseline_duration="${DURATIONS[0]}"

for i in "${!LABELS[@]}"; do
    label="${LABELS[$i]}"
    duration="${DURATIONS[$i]}"

    if [[ "$duration" == "FAILED" || "$duration" == "N/A" ]]; then
        printf "%-20s | %10s | %10s\n" "$label" "$duration" "-"
    elif [[ "$baseline_duration" != "FAILED" && "$baseline_duration" != "N/A" && "$baseline_duration" -gt 0 ]]; then
        speedup=$(echo "scale=2; $baseline_duration / $duration" | bc 2>/dev/null || echo "-")
        printf "%-20s | %8ss | %9sx\n" "$label" "$duration" "$speedup"
    else
        printf "%-20s | %8ss | %10s\n" "$label" "$duration" "-"
    fi
done

echo ""
echo "Note: Run each query 3 times and report median for reliable results."
echo "See docs/benchmark-plan.md for detailed methodology."
