#!/bin/bash
# Remove Kafbat UI
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

source "$PROJECT_ROOT/scripts/common/utils.sh"
source "$PROJECT_ROOT/scripts/common/config-loader.sh"

NAMESPACE="${KAFKA_UI_NAMESPACE:-kafka}"

print_info "Removing Kafbat UI"
echo "=========================================="

helm uninstall kafka-ui -n "$NAMESPACE" --ignore-not-found 2>/dev/null || true
print_success "  Helm release removed"

print_success "Kafbat UI Removed!"
