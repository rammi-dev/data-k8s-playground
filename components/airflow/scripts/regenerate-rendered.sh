#!/bin/bash
# Regenerate rendered Helm templates from current values
# Output: helm/rendered/ (gitignored)
#
# Usage: regenerate-rendered.sh [--clean]
#   --clean   Delete empty template files after rendering
set -e

CLEAN_EMPTY=false
[[ "${1:-}" == "--clean" ]] && CLEAN_EMPTY=true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELM_DIR="$(cd "$SCRIPT_DIR/../helm" && pwd)"
RENDERED_DIR="$HELM_DIR/rendered"

# Clean old rendered content (preserve .gitignore)
find "$RENDERED_DIR" -mindepth 1 ! -name '.gitignore' -exec rm -rf {} + 2>/dev/null || true

# Render templates
helm template airflow "$HELM_DIR" \
    --namespace airflow \
    --values "$HELM_DIR/values.yaml" \
    --output-dir "$RENDERED_DIR/"

echo ""
TOTAL=$(find "$RENDERED_DIR" -name '*.yaml' | wc -l)
echo "Rendered $TOTAL files to $RENDERED_DIR/"

# Report empty files (templates that rendered to just a header comment)
EMPTY_FILES=()
while IFS= read -r f; do
    # Strip comments and blank lines — if nothing remains, the file is effectively empty
    if ! grep -qE '^[^#]' "$f" 2>/dev/null; then
        EMPTY_FILES+=("$f")
    fi
done < <(find "$RENDERED_DIR" -name '*.yaml' -type f | sort)

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
        # Remove empty directories left behind
        find "$RENDERED_DIR" -type d -empty -delete 2>/dev/null || true
        echo ""
        echo "Deleted ${#EMPTY_FILES[@]} empty files (--clean)"
    fi
    echo ""
    echo "Active: $((TOTAL - ${#EMPTY_FILES[@]}))  |  Empty: ${#EMPTY_FILES[@]}  |  Total: $TOTAL"
fi
