# Data Lakehouse — C4 Architecture Documentation

C4 model architecture documentation for the Data Lakehouse platform on OpenShift.

**Single source of truth:** [`workspace.dsl`](workspace.dsl) (Structurizr DSL)

Everything else is **generated** from the DSL:
- `diagrams/generated/*.puml` → PlantUML diagrams (via `structurizr-cli export`)
- `diagrams/generated/*.svg` → rendered SVG images (via `plantuml`)
- `levels/*.md` → markdown documentation with embedded diagrams (via `generate-docs.py`)

## Pipeline

```
workspace.dsl  ──→  structurizr-cli export  ──→  .puml + .json
                                                    │         │
                                          plantuml -tsvg   generate-docs.py
                                                    │         │
                                                  .svg    levels/*.md (with embedded SVG)
```

## Generated Documentation

| Level | Document | Description |
|-------|----------|-------------|
| L0 | [Design Principles](levels/L0-design-principles.md) | C4 level separation guidelines |
| L1 | [System Context](levels/L1-system-context.md) | Actors, external systems, Lakehouse boundary |
| L2 | [Containers](levels/L2-containers.md) | Logical deployable services (incl. MongoDB) |
| L3 | [Dremio Components](levels/L3-components-dremio.md) | Query engine logical modules |
| L3 | [Superset Components](levels/L3-components-superset.md) | BI platform (placeholder) |
| L3 | [Spark Components](levels/L3-components-spark.md) | Batch compute (placeholder) |
| L3 | [Airflow Components](levels/L3-components-airflow.md) | Workflow orchestration (placeholder) |
| L3 | [JupyterHub Components](levels/L3-components-jupyterhub.md) | Notebooks (placeholder) |
| L4 | [Deployment (OCP)](levels/L4-deployment-ocp.md) | Container boundaries overview, runtime units, monitoring endpoints |
| L4 | [Dremio Deployment](levels/L4-deployment-dremio.md) | Dremio boundary runtime units (TODO) |
| L4 | [MongoDB Deployment](levels/L4-deployment-mongodb.md) | MongoDB boundary runtime units |
| L4 | [Superset Deployment](levels/L4-deployment-superset.md) | Superset boundary runtime units (TODO) |
| L4 | [Spark Deployment](levels/L4-deployment-spark.md) | Spark boundary runtime units (TODO) |
| L4 | [Airflow Deployment](levels/L4-deployment-airflow.md) | Airflow boundary runtime units (TODO) |
| L4 | [JupyterHub Deployment](levels/L4-deployment-jupyterhub.md) | JupyterHub boundary runtime units (TODO) |

> L1-L4 files are auto-generated from `workspace.dsl`. L0 is hand-maintained.

## Quick Start

```bash
# Generate everything (auto-detects local tools or Docker)
./docs/architecture/scripts/generate-diagrams.sh

# Force Docker mode (no local Java needed)
./docs/architecture/scripts/generate-diagrams.sh --docker
```

The script runs a 6-step pipeline:
1. Validate `workspace.dsl`
2. Export DSL → PlantUML (`.puml`)
3. Post-process `.puml` for readability (wider boxes, smaller fonts so descriptions fit)
4. Export DSL → JSON
5. Render PlantUML → SVG
6. Generate markdown docs from JSON

## Tooling Setup

Two workflows: **VS Code** for daily editing and **CLI** for generation.

### Prerequisites

| Tool | Purpose | Required by |
|------|---------|-------------|
| Java 17+ | Runs Structurizr CLI and PlantUML | Local CLI |
| Graphviz | PlantUML diagram layout engine | Local CLI |
| Python 3 | Runs generate-docs.py | Both |
| Docker | Alternative to local Java (runs tools in containers) | Docker CLI |

### Workflow 1: VS Code (daily editing)

Install these VS Code extensions:

1. **`ciarant.vscode-structurizr`** — Structurizr DSL syntax highlighting and validation
   ```
   code --install-extension ciarant.vscode-structurizr
   ```

2. **`jebbs.plantuml`** — PlantUML live preview (`Alt+D` to preview), SVG/PNG export
   ```
   code --install-extension jebbs.plantuml
   ```
   Requires Java 17+ and Graphviz locally, or configure to use a PlantUML server:
   ```jsonc
   // .vscode/settings.json
   {
     "plantuml.server": "https://www.plantuml.com/plantuml",
     "plantuml.render": "PlantUMLServer"
   }
   ```

3. **`hediet.vscode-drawio`** *(optional)* — Draw.io integration for manual diagram refinement
   ```
   code --install-extension hediet.vscode-drawio
   ```

**Daily workflow:**
1. Edit `workspace.dsl` (syntax highlighting from structurizr extension)
2. Run `./docs/architecture/scripts/generate-diagrams.sh` to regenerate everything
3. Open `.puml` in VS Code → `Alt+D` for live PlantUML preview
4. Review generated `levels/*.md` — they reflect your DSL changes automatically

### Workflow 2: CLI (transform / export / CI)

#### Option A: Local installation

```bash
# Install Java 17+ and Graphviz (Ubuntu/Debian)
sudo apt install default-jre graphviz

# Install PlantUML
sudo apt install plantuml

# Install Structurizr CLI (v2025.11.09+)
# Download from: https://github.com/structurizr/cli/releases
curl -L -o /tmp/structurizr-cli.zip \
  https://github.com/structurizr/cli/releases/download/v2025.11.09/structurizr-cli.zip
mkdir -p ~/.local/share/structurizr-cli
unzip -o /tmp/structurizr-cli.zip -d ~/.local/share/structurizr-cli
rm /tmp/structurizr-cli.zip

# Create wrapper script on PATH
mkdir -p ~/.local/bin
cat > ~/.local/bin/structurizr-cli << 'WRAPPER'
#!/usr/bin/env bash
STRUCTURIZR_DIR="$HOME/.local/share/structurizr-cli"
exec java -cp "$STRUCTURIZR_DIR:$STRUCTURIZR_DIR/lib/*" com.structurizr.cli.StructurizrCliApplication "$@"
WRAPPER
chmod +x ~/.local/bin/structurizr-cli

# Verify
structurizr-cli version
```

> **Note:** Ensure `~/.local/bin` is on your PATH. Add `export PATH="$HOME/.local/bin:$PATH"` to `~/.bashrc` if needed.

#### Option B: Docker (no local Java needed)

```bash
docker pull structurizr/cli:latest
docker pull plantuml/plantuml:latest
```

#### Manual CLI commands

```bash
# Validate
structurizr-cli validate -workspace docs/architecture/workspace.dsl

# Export DSL → PlantUML
structurizr-cli export -workspace docs/architecture/workspace.dsl \
  -format plantuml/structurizr -output docs/architecture/diagrams/generated/

# Export DSL → JSON (for docs generation)
structurizr-cli export -workspace docs/architecture/workspace.dsl \
  -format json -output /tmp/

# Render PlantUML → SVG
plantuml -tsvg docs/architecture/diagrams/generated/*.puml

# Generate markdown docs
python3 docs/architecture/scripts/generate-docs.py /tmp/structurizr-*.json docs/architecture/levels/
```

## How to Edit

1. Open `workspace.dsl` in VS Code
2. Add/modify elements, relationships, or properties
3. Run `./docs/architecture/scripts/generate-diagrams.sh`
4. Commit the updated `workspace.dsl` and generated files

**Adding detail to generated docs:** Use `properties` blocks on DSL elements. The generator renders them as tables in the markdown output.

```dsl
component "My Component" "Description here" {
    properties {
        "Port" ":8080"
        "Metrics" "/metrics"
        "CPU" "500m request / 2 limit"
    }
}
```

## Other Files

| File | Purpose |
|------|---------|
| [adr/001-structurizr-dsl-choice.md](adr/001-structurizr-dsl-choice.md) | ADR: Why Structurizr DSL |
| [diagrams/custom/](diagrams/custom/) | Hand-crafted PlantUML (not generated) |
| [scripts/generate-diagrams.sh](scripts/generate-diagrams.sh) | Full pipeline script |
| [scripts/generate-docs.py](scripts/generate-docs.py) | JSON → markdown generator |
