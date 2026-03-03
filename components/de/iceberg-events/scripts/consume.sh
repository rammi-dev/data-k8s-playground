#!/bin/bash
# Consume S3 notification events from Kafka and display to stdout
# Uses Strimzi kafka-console-consumer via ephemeral pod
set -e

# Determine project root
if [[ -d "/vagrant" ]]; then
    PROJECT_ROOT="/vagrant"
elif [[ -n "${PROJECT_ROOT:-}" ]]; then
    :
else
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
fi

KAFKA_NAMESPACE="iceberg-events"
TOPIC="iceberg-events-topic"
BOOTSTRAP="events-kafka-kafka-bootstrap:9092"
STRIMZI_IMAGE="quay.io/strimzi/kafka:0.50.0-kafka-4.1.1"

# Options
FROM_BEGINNING=false
TIMEOUT_MS=""

usage() {
    echo "Usage: $(basename "$0") [OPTIONS]"
    echo ""
    echo "Consume S3 notification events from Kafka topic '$TOPIC'"
    echo ""
    echo "Options:"
    echo "  -b, --from-beginning   Read all events from the beginning of the topic"
    echo "  -t, --timeout MS       Exit after MS milliseconds of no new messages"
    echo "  -h, --help             Show this help"
    echo ""
    echo "Press Ctrl+C to stop consuming."
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -b|--from-beginning) FROM_BEGINNING=true; shift ;;
        -t|--timeout) TIMEOUT_MS="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1"; usage; exit 1 ;;
    esac
done

source "$PROJECT_ROOT/scripts/common/utils.sh"

# Build consumer args
CONSUMER_ARGS=(
    bin/kafka-console-consumer.sh
    --bootstrap-server "$BOOTSTRAP"
    --topic "$TOPIC"
    --property print.key=true
    --property print.timestamp=true
    --property key.separator=" | "
)

if [[ "$FROM_BEGINNING" == "true" ]]; then
    CONSUMER_ARGS+=(--from-beginning)
fi

if [[ -n "$TIMEOUT_MS" ]]; then
    CONSUMER_ARGS+=(--timeout-ms "$TIMEOUT_MS")
fi

# Delete leftover consumer pod if it exists
kubectl -n "$KAFKA_NAMESPACE" delete pod kafka-consumer --ignore-not-found --wait=false &>/dev/null

print_info "Consuming from topic '$TOPIC' (namespace: $KAFKA_NAMESPACE)"
print_info "Press Ctrl+C to stop"
echo "---"

kubectl -n "$KAFKA_NAMESPACE" run kafka-consumer -ti --rm \
    --image="$STRIMZI_IMAGE" \
    --restart=Never \
    -- "${CONSUMER_ARGS[@]}"
