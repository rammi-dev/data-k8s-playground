# Data Lakehouse — C4 Architecture Documentation

Architecture documentation for the Data Lakehouse platform on OpenShift. Inspired by the [C4 model](https://c4model.com/) (software architecture), adapted here for platform and infrastructure documentation.

**C4 modeling guidelines:** [`L0-design-principles`](levels/L0-design-principles.md) — zasady podziału na poziomy L1–L4, reguły granulacji, kiedy element promować do osobnego kontenera, kiedy grupować.

**Single source of truth:** [`workspace.dsl`](workspace.dsl) (Structurizr DSL)

Two types of content are combined into the final documentation:
- **Generated from DSL** — diagrams (`.puml`, `.svg`) and markdown structure (`levels/*.md`) via `structurizr-cli` + `generate-docs.py`
- **Hand-maintained extras** — [`extras/*.md`](extras/) files with detailed descriptions, Mermaid diagrams, K8s object tables, networking/storage sections — merged into generated `levels/*.md` by `generate-docs.py`

## Pipeline

```
workspace.dsl  ──→  structurizr-cli export  ──→  .puml + .json
                                                    │         │
                                          plantuml -tsvg   generate-docs.py ←── extras/*.md
                                                    │         │                  (hand-maintained)
                                                  .svg    levels/*.md
                                                          (DSL properties + extras merged)
```

**Flow szczegółowo:**

1. `workspace.dsl` → **structurizr-cli validate** — walidacja składni DSL
2. `workspace.dsl` → **structurizr-cli export** → `.puml` (PlantUML) + `.json` (model danych)
3. `.puml` → **post-process** (szersze boxy, mniejszy font) → **plantuml -tsvg** → `.svg`
4. `.json` + `extras/*.md` → **generate-docs.py** → `levels/*.md`
   - Właściwości (`properties {}`) z DSL → tabele w markdown (automatycznie)
   - Pliki `extras/<nazwa>.md` → dołączane na końcu odpowiedniego `levels/<nazwa>.md` (ręcznie utrzymywane)

**Przykład:** `extras/L4-deployment-mongodb.md` zawiera Mermaid diagram, tabele obiektów K8s, sekcje networking/storage. `generate-docs.py` łączy go z wygenerowanymi właściwościami DSL i zapisuje jako `levels/L4-deployment-mongodb.md`.

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
| L4 | [Dremio Deployment](levels/L4-deployment-dremio.md) | Dremio boundary runtime units |
| L4 | [MongoDB Deployment](levels/L4-deployment-mongodb.md) | MongoDB boundary runtime units |
| L4 | [Superset Deployment](levels/L4-deployment-superset.md) | Superset boundary runtime units (TODO) |
| L4 | [Spark Deployment](levels/L4-deployment-spark.md) | Spark boundary runtime units (TODO) |
| L4 | [Airflow Deployment](levels/L4-deployment-airflow.md) | Airflow boundary runtime units (TODO) |
| L4 | [JupyterHub Deployment](levels/L4-deployment-jupyterhub.md) | JupyterHub boundary runtime units (TODO) |

> **L0** jest utrzymywany ręcznie — definiuje zasady modelowania C4.
> **L1–L4** pliki w `levels/` są generowane automatycznie z `workspace.dsl` + `extras/`.
> Pliki `extras/*.md` są utrzymywane ręcznie i zawierają szczegółowe opisy architektoniczne (Mermaid, tabele K8s, networking, storage).

## Quick Start

```bash
# Generate everything (auto-detects local tools or Docker)
./docs/architecture/scripts/generate-diagrams.sh

# Force Docker mode (no local Java needed)
./docs/architecture/scripts/generate-diagrams.sh --docker
```

Skrypt uruchamia pipeline w 6 krokach:
1. Walidacja `workspace.dsl`
2. Eksport DSL → PlantUML (`.puml`)
3. Post-processing `.puml` (szersze boxy, mniejszy font dla czytelności)
4. Eksport DSL → JSON
5. Rendering PlantUML → SVG
6. Generowanie markdown z JSON + łączenie z `extras/*.md`

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

Dwa sposoby dodawania treści do dokumentacji:

### Sposób 1: Właściwości DSL (automatycznie generowane tabele)

1. Otwórz `workspace.dsl` w VS Code
2. Dodaj/zmień elementy, relacje lub `properties {}`
3. Uruchom `./docs/architecture/scripts/generate-diagrams.sh`
4. Commituj `workspace.dsl` i wygenerowane pliki

```dsl
deploymentNode "dremio-master" "" "StatefulSet (1 replica)" {
    properties {
        "Purpose" "Koordynator zapytań — parsowanie SQL, planowanie"
        "Ports" ":9047 (Web UI), :31010 (ODBC/JDBC), :45678 (fabric)"
        "Resources" "requests: 4/16Gi, limits: 4/16Gi"
    }
}
```

### Sposób 2: Pliki extras/ (ręcznie utrzymywane opisy)

1. Utwórz lub edytuj plik w `extras/` o nazwie odpowiadającej docelowemu `levels/*.md`
   - np. `extras/L4-deployment-dremio.md` → łączony z `levels/L4-deployment-dremio.md`
2. Dodaj szczegółowe sekcje: opis architektury, diagram Mermaid, tabele obiektów K8s, networking, storage
3. Zacznij plik od komentarza wskazującego źródło:
   ```
   <!-- Included in: levels/L4-deployment-dremio.md (deployment boundary, via extras/) -->
   <!-- Source: components/dremio/helm/ (rendered Helm templates + values-overrides.yaml) -->
   ```
4. Uruchom `./docs/architecture/scripts/generate-diagrams.sh` — treść extras zostanie dołączona po sekcjach wygenerowanych z DSL
5. Commituj `extras/*.md`, `workspace.dsl` i wygenerowane pliki

## Other Files

| File | Purpose |
|------|---------|
| [levels/L0-design-principles.md](levels/L0-design-principles.md) | Zasady modelowania C4 — separacja poziomów L1–L4, reguły granulacji |
| [extras/](extras/) | Ręcznie utrzymywane opisy architektoniczne (Mermaid, K8s, networking, storage) — łączone z `levels/` |
| [adr/001-structurizr-dsl-choice.md](adr/001-structurizr-dsl-choice.md) | ADR: Why Structurizr DSL |
| [diagrams/custom/](diagrams/custom/) | Hand-crafted PlantUML (not generated) |
| [scripts/generate-diagrams.sh](scripts/generate-diagrams.sh) | Full pipeline script |
| [scripts/generate-docs.py](scripts/generate-docs.py) | JSON + extras → markdown generator |
