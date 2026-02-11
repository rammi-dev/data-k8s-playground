#!/usr/bin/env bash
# generate-diagrams.sh — Full pipeline: DSL → JSON + PlantUML → post-process → SVG → Markdown docs
#
# Usage:
#   ./docs/architecture/scripts/generate-diagrams.sh           # auto-detect local or Docker
#   ./docs/architecture/scripts/generate-diagrams.sh --docker   # force Docker mode
#   ./docs/architecture/scripts/generate-diagrams.sh --local    # force local mode

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARCH_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKSPACE="$ARCH_DIR/workspace.dsl"
OUTPUT_DIR="$ARCH_DIR/diagrams/generated"
LEVELS_DIR="$ARCH_DIR/levels"
TMP_DIR="${TMPDIR:-/tmp}/structurizr-export"

MODE="${1:-auto}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
step()  { echo -e "${CYAN}[STEP]${NC} $*"; }

has_cmd() { command -v "$1" &>/dev/null; }

detect_mode() {
    if [[ "$MODE" == "--docker" ]]; then
        if ! has_cmd docker; then
            error "Docker not found. Install Docker or use --local mode."
            exit 1
        fi
        echo "docker"
    elif [[ "$MODE" == "--local" ]]; then
        if ! has_cmd structurizr-cli; then
            error "structurizr-cli not found. Install it or use --docker mode."
            exit 1
        fi
        echo "local"
    else
        if has_cmd structurizr-cli; then
            echo "local"
        elif has_cmd docker; then
            echo "docker"
        else
            error "Neither structurizr-cli nor Docker found."
            error "Install one of:"
            error "  - structurizr-cli: https://github.com/structurizr/cli/releases"
            error "  - Docker: https://docs.docker.com/get-docker/"
            exit 1
        fi
    fi
}

# Step 1: Validate DSL
validate_dsl() {
    step "1/7  Validating workspace.dsl..."
    if [[ "$RESOLVED_MODE" == "local" ]]; then
        structurizr-cli validate -workspace "$WORKSPACE"
    else
        docker run --rm \
            -v "$ARCH_DIR:/workspace" \
            structurizr/cli:latest \
            validate -workspace /workspace/workspace.dsl
    fi
}

# Step 2: Export DSL → PlantUML
export_plantuml() {
    step "2/7  Exporting DSL → PlantUML (.puml)..."
    mkdir -p "$OUTPUT_DIR"

    if [[ "$RESOLVED_MODE" == "local" ]]; then
        structurizr-cli export \
            -workspace "$WORKSPACE" \
            -format plantuml/structurizr \
            -output "$OUTPUT_DIR"
    else
        docker run --rm \
            -v "$ARCH_DIR:/workspace" \
            structurizr/cli:latest \
            export \
            -workspace /workspace/workspace.dsl \
            -format plantuml/structurizr \
            -output /workspace/diagrams/generated
    fi
}

# Step 3: Post-process PlantUML for readability
postprocess_puml() {
    step "3/7  Post-processing PlantUML for readability..."

    local puml_count
    puml_count=$(find "$OUTPUT_DIR" -name "*.puml" 2>/dev/null | wc -l)

    if [[ "$puml_count" -eq 0 ]]; then
        warn "No .puml files to post-process."
        return
    fi

    for f in "$OUTPUT_DIR"/*.puml; do
        # Widen element boxes: 450 → 700 (descriptions fit ~35 chars/line instead of ~18)
        sed -i 's/MaximumWidth: 450;/MaximumWidth: 700;/g' "$f"
        # Reduce element font size: 24 → 16 (keeps diagrams compact)
        sed -i 's/FontSize: 24;/FontSize: 16;/g' "$f"
        # Reduce title size
        sed -i 's/<size:24>/<size:18>/g' "$f"
        # Reduce type label size
        sed -i 's/<size:16>/<size:12>/g' "$f"
        # Remove description subtitle from diagram titles (too long, unreadable;
        # descriptions are already in the markdown docs)
        sed -i '/^title /s/\\n<size:[0-9]*>.*$//' "$f"
    done

    info "Post-processed $puml_count .puml files (wider boxes, smaller fonts)."
}

# Step 4: Export DSL → JSON (for docs generation)
export_json() {
    step "4/7  Exporting DSL → JSON..."
    mkdir -p "$TMP_DIR"

    if [[ "$RESOLVED_MODE" == "local" ]]; then
        structurizr-cli export \
            -workspace "$WORKSPACE" \
            -format json \
            -output "$TMP_DIR"
    else
        docker run --rm \
            -v "$ARCH_DIR:/workspace" \
            -v "$TMP_DIR:/output" \
            structurizr/cli:latest \
            export \
            -workspace /workspace/workspace.dsl \
            -format json \
            -output /output
    fi
}

# Step 5: Render PlantUML → SVG
render_svg() {
    local puml_count
    puml_count=$(find "$OUTPUT_DIR" -name "*.puml" 2>/dev/null | wc -l)

    if [[ "$puml_count" -eq 0 ]]; then
        warn "No .puml files found — skipping SVG render."
        return
    fi

    step "5/7  Rendering PlantUML → SVG ($puml_count files)..."

    if [[ "$RESOLVED_MODE" == "local" ]]; then
        if has_cmd plantuml; then
            plantuml -tsvg "$OUTPUT_DIR"/*.puml
        elif [[ -n "${PLANTUML_JAR:-}" && -f "$PLANTUML_JAR" ]]; then
            java -jar "$PLANTUML_JAR" -tsvg "$OUTPUT_DIR"/*.puml
        else
            warn "plantuml not found and PLANTUML_JAR not set."
            warn ".puml files are ready for manual rendering or VS Code preview (Alt+D)."
            return
        fi
    else
        docker run --rm \
            -v "$OUTPUT_DIR:/data" \
            plantuml/plantuml:latest \
            -tsvg "/data/*.puml"
    fi
}

# Step 6: Generate markdown docs from JSON
generate_docs() {
    step "6/7  Generating markdown documentation..."

    # Find the exported JSON file
    local json_file
    json_file=$(find "$TMP_DIR" -name "structurizr-*.json" -o -name "*.json" 2>/dev/null | head -1)

    if [[ -z "$json_file" ]]; then
        warn "No JSON export found in $TMP_DIR — skipping docs generation."
        warn "Make sure structurizr-cli export -format json succeeded."
        return
    fi

    if ! has_cmd python3; then
        warn "python3 not found — skipping docs generation."
        warn "Install Python 3 or run manually: python3 scripts/generate-docs.py <json> levels/"
        return
    fi

    mkdir -p "$LEVELS_DIR"
    python3 "$SCRIPT_DIR/generate-docs.py" "$json_file" "$LEVELS_DIR" "$OUTPUT_DIR"
}

# Step 7: Copy SVGs into levels/svg/ for self-contained export
copy_svgs() {
    step "7/7  Copying SVG diagrams to levels/svg/..."

    local svg_dir="$LEVELS_DIR/svg"
    rm -rf "$svg_dir"
    mkdir -p "$svg_dir"

    local count=0
    for md_file in "$LEVELS_DIR"/*.md; do
        # Extract SVG references from markdown image links (svg/filename.svg)
        while IFS= read -r svg_name; do
            local src="$OUTPUT_DIR/$svg_name"
            if [[ -f "$src" && ! -f "$svg_dir/$svg_name" ]]; then
                cp "$src" "$svg_dir/$svg_name"
                count=$((count + 1))
            fi
        done < <(grep -oP '(?<=\()svg/\K[^)]+\.svg' "$md_file" 2>/dev/null || true)
    done

    info "Copied $count SVG files to $svg_dir/"
}

# Cleanup temp files
cleanup() {
    if [[ -d "$TMP_DIR" ]]; then
        rm -rf "$TMP_DIR"
    fi
}

# Main
main() {
    RESOLVED_MODE="$(detect_mode)"
    info "Mode: $RESOLVED_MODE"
    info "Workspace: $WORKSPACE"
    info "Diagrams:  $OUTPUT_DIR"
    info "Docs:      $LEVELS_DIR"
    echo ""

    trap cleanup EXIT

    validate_dsl
    echo ""
    export_plantuml
    echo ""
    postprocess_puml
    echo ""
    export_json
    echo ""
    render_svg
    echo ""
    generate_docs
    echo ""
    copy_svgs

    echo ""
    info "Pipeline complete."
    info "Diagrams: $OUTPUT_DIR/"
    info "Docs:     $LEVELS_DIR/"
    ls -la "$OUTPUT_DIR"/ 2>/dev/null || true
}

main "$@"
