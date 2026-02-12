#!/bin/bash
# Regenerate rendered Helm templates for the Rook operator
# Output: deployment/rendered/ (for reference only)
#
# Cluster CRDs are static manifests in manifests/ — not rendered here.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
COMPONENT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RENDERED_DIR="$COMPONENT_DIR/deployment/rendered"

source "$PROJECT_ROOT/scripts/common/config-loader.sh"

echo "Regenerating Rook Operator Helm templates"
echo "Chart version: $CEPH_CHART_VERSION"
echo "Namespace:     $CEPH_NAMESPACE"
echo "Output:        $RENDERED_DIR/"
echo ""

# ============================================================================
# STEP 1: Clean old rendered content
# ============================================================================
rm -rf "$RENDERED_DIR"
mkdir -p "$RENDERED_DIR"

# ============================================================================
# STEP 2: Add Helm repo
# ============================================================================
echo "Adding Rook Helm repository..."
helm repo add rook-release "$CEPH_CHART_REPO" 2>/dev/null || true
helm repo update
echo ""

# ============================================================================
# STEP 3: Render operator chart
# ============================================================================
echo "Rendering Rook Operator chart..."
helm template rook-ceph-operator rook-release/rook-ceph \
    --namespace "$CEPH_NAMESPACE" \
    --version "$CEPH_CHART_VERSION" \
    --output-dir "$RENDERED_DIR/operator"

echo ""

# ============================================================================
# STEP 4: Copy manifests for reference
# ============================================================================
MANIFESTS_SRC="$COMPONENT_DIR/manifests"
MANIFESTS_DST="$RENDERED_DIR/manifests"

if [[ -d "$MANIFESTS_SRC" ]]; then
    echo "Copying cluster manifests for reference..."
    mkdir -p "$MANIFESTS_DST"
    cp -r "$MANIFESTS_SRC"/* "$MANIFESTS_DST/"
    echo "  Copied: manifests/ → deployment/rendered/manifests/"
    echo ""
fi

# ============================================================================
# STEP 5: Report
# ============================================================================
TOTAL=$(find "$RENDERED_DIR" -name '*.yaml' -type f | wc -l)
echo "Rendered $TOTAL files to $RENDERED_DIR/"
echo ""
echo "  Operator: $RENDERED_DIR/operator/"
echo "  Manifests: $RENDERED_DIR/manifests/ (cluster CRDs — applied by create-cluster.sh)"
echo ""
