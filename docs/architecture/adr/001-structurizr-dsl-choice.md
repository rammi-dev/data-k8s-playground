# ADR-001: Structurizr DSL as Architecture Documentation Source of Truth

## Status

Accepted

## Context

The Data Lakehouse platform needs architecture documentation that covers multiple C4 levels (System Context, Containers, Components, Deployment). The documentation must be:

- Version-controlled alongside code
- Easy to maintain and update as the platform evolves
- Exportable to visual diagrams (PlantUML, SVG)
- Usable in both VS Code (daily editing) and CLI (CI/CD export)

Options considered:

1. **Structurizr DSL** — text-based DSL for C4 models, exports to PlantUML/Mermaid/SVG
2. **Hand-crafted PlantUML** — manual PlantUML files per diagram
3. **Draw.io / diagrams.net** — GUI-based XML diagram files
4. **Mermaid** — inline markdown diagrams (already used in some docs)

## Decision

Use **Structurizr DSL** (`workspace.dsl`) as the single source of truth for all C4 architecture diagrams.

## Rationale

- **Single source, multiple views:** One DSL file defines the entire model. All C4 levels (L1–L4) are generated from the same model, ensuring consistency.
- **Text-based and diffable:** DSL files are plain text, making them easy to review in PRs, track changes, and resolve merge conflicts.
- **Automated export:** `structurizr-cli export` produces PlantUML files. PlantUML renders to SVG/PNG. Both can run locally or in Docker (no Java dependency with Docker).
- **IDE support:** VS Code extension (`ciarant.vscode-structurizr`) provides syntax highlighting. PlantUML extension (`jebbs.plantuml`) provides live preview.
- **C4 model alignment:** Structurizr DSL is designed specifically for C4, enforcing proper level separation (system → container → component → deployment).
- **Layered documentation:** Each C4 level has a companion markdown file that provides narrative context. The DSL handles the visual model; markdown handles the written documentation.

### Trade-offs

- Requires Java 17+ or Docker to run `structurizr-cli` and `plantuml`
- Learning curve for DSL syntax (mitigated by VS Code extension and examples)
- Generated PlantUML may need manual style tweaks for complex diagrams — use `diagrams/custom/` for hand-crafted overrides

## Consequences

- All architecture diagrams are generated from `workspace.dsl`
- Manual diagram refinements go in `diagrams/custom/` (not generated)
- CI/CD can validate DSL syntax and regenerate diagrams automatically
- Contributors must learn basic Structurizr DSL syntax to modify architecture docs
