#!/bin/bash
# Regenerate rendered Helm templates for inspection
# Output: deployment/rendered/ (gitignored)
#
# Usage: regenerate-rendered.sh [--clean]
#   --clean   Delete empty template files after rendering
#
# This is useful for:
#   - Inspecting what Helm will deploy
#   - Debugging template issues
#   - Understanding operator configuration
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

echo "Regenerating CloudNativePG Helm templates"
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

helm template postgres-operator "$HELM_DIR" \
    --namespace postgres-operator \
    --values "$VALUES_BASE" \
    --values "$VALUES_OVERRIDE" \
    --output-dir "$RENDERED_DIR/"

echo ""

# ============================================================================
# STEP 4: Copy custom manifests (test clusters)
# ============================================================================
CUSTOM_SRC="$HELM_DIR/templates/custom"
CUSTOM_DST="$RENDERED_DIR/custom"

if [[ -d "$CUSTOM_SRC" ]]; then
    echo "Copying custom manifests..."
    mkdir -p "$CUSTOM_DST"
    cp -r "$CUSTOM_SRC"/* "$CUSTOM_DST/"
    echo "  Copied: templates/custom/ → deployment/rendered/custom/"
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
done < <(find "$RENDERED_DIR" -name '*.yaml' -type f -not -path "*/custom/*" | sort)

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
        find "$RENDERED_DIR" -type d -empty -not -path "$CUSTOM_DST" -delete 2>/dev/null || true
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
echo "  kubectl apply -f $RENDERED_DIR/postgres-playground/templates/"
echo "  kubectl apply -f $RENDERED_DIR/custom/"
