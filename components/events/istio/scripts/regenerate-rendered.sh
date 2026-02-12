#!/bin/bash
# Regenerate rendered Helm templates for inspection
# Output: deployment/rendered/ (gitignored)
#
# Usage: regenerate-rendered.sh [--clean]
#   --clean   Delete empty template files after rendering
set -e

CLEAN_EMPTY=false
[[ "${1:-}" == "--clean" ]] && CLEAN_EMPTY=true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPONENT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HELM_DIR="$COMPONENT_DIR/helm"
RENDERED_DIR="$COMPONENT_DIR/deployment/rendered"

VALUES_BASE="$HELM_DIR/values.yaml"
VALUES_OVERRIDE="$HELM_DIR/values-overrides.yaml"

# Validate files exist
for f in "$VALUES_BASE" "$VALUES_OVERRIDE"; do
    if [[ ! -f "$f" ]]; then
        echo "Error: Not found: $f"
        exit 1
    fi
done

echo "Regenerating Istio Helm templates"
echo "Base values:  $VALUES_BASE"
echo "Overrides:    $VALUES_OVERRIDE"
echo "Output:       $RENDERED_DIR/"
echo ""

# ============================================================================
# STEP 1: Clean old rendered content
# ============================================================================
rm -rf "$RENDERED_DIR"
mkdir -p "$RENDERED_DIR"

# ============================================================================
# STEP 2: Update Helm dependencies
# ============================================================================
echo "Updating Helm dependencies..."
helm dependency update "$HELM_DIR"
echo ""

# ============================================================================
# STEP 3: Render Helm templates
# ============================================================================
echo "Rendering Helm templates..."

helm template istio "$HELM_DIR" \
    --namespace istio-system \
    --values "$VALUES_BASE" \
    --values "$VALUES_OVERRIDE" \
    --output-dir "$RENDERED_DIR/"

echo ""

# ============================================================================
# STEP 4: Copy manifests (operator-dependent CRs applied by build.sh)
# ============================================================================
MANIFESTS_SRC="$COMPONENT_DIR/manifests"
MANIFESTS_DST="$RENDERED_DIR/manifests"

if [[ -d "$MANIFESTS_SRC" ]]; then
    echo "Copying manifests..."
    mkdir -p "$MANIFESTS_DST"
    cp -r "$MANIFESTS_SRC"/* "$MANIFESTS_DST/"
    echo "  Copied: manifests/ → deployment/rendered/manifests/"
    echo ""
fi

# ============================================================================
# STEP 5: Report results
# ============================================================================
TOTAL=$(find "$RENDERED_DIR" -name '*.yaml' -type f | wc -l)
echo "Rendered $TOTAL files to $RENDERED_DIR/"

# Find empty files
EMPTY_FILES=()
while IFS= read -r f; do
    if ! grep -qE '^[^#]' "$f" 2>/dev/null; then
        EMPTY_FILES+=("$f")
    fi
done < <(find "$RENDERED_DIR" -name '*.yaml' -type f -not -path "*/manifests/*" | sort)

if [[ ${#EMPTY_FILES[@]} -gt 0 ]]; then
    echo ""
    echo "Empty templates (no K8s objects rendered):"
    for f in "${EMPTY_FILES[@]}"; do
        echo "  - ${f#$RENDERED_DIR/}"
    done

    if [[ "$CLEAN_EMPTY" == "true" ]]; then
        for f in "${EMPTY_FILES[@]}"; do
            rm "$f"
        done
        find "$RENDERED_DIR" -type d -empty -not -path "$MANIFESTS_DST" -delete 2>/dev/null || true
        echo ""
        echo "Deleted ${#EMPTY_FILES[@]} empty files (--clean)"
    fi

    echo ""
    echo "Active: $((TOTAL - ${#EMPTY_FILES[@]}))  |  Empty: ${#EMPTY_FILES[@]}  |  Total: $TOTAL"
fi

echo ""
echo "Rendered templates are in: $RENDERED_DIR/"
echo ""
echo "To deploy rendered templates:"
echo "  kubectl apply -f $RENDERED_DIR/istio-playground/templates/"
echo "  kubectl apply -f $RENDERED_DIR/manifests/"
