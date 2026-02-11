#!/usr/bin/env python3
"""
Generate C4 architecture documentation from Structurizr workspace JSON.

Reads the JSON export from structurizr-cli and generates one markdown file
per view, with embedded PlantUML diagrams, element descriptions, properties,
and relationship tables.

Usage:
    structurizr-cli export -workspace workspace.dsl -format json -output /tmp
    python3 generate-docs.py /tmp/structurizr-DataLakehouse.json levels/ diagrams/generated/
"""

import json
import sys
from pathlib import Path

# Map view keys to output filenames
VIEW_KEY_TO_FILENAME = {
    "L1_SystemContext": "L1-system-context.md",
    "L2_Containers": "L2-containers.md",
    "L3_Components_Dremio": "L3-components-dremio.md",
    "L3_Components_Superset": "L3-components-superset.md",
    "L3_Components_Spark": "L3-components-spark.md",
    "L3_Components_Airflow": "L3-components-airflow.md",
    "L3_Components_JupyterHub": "L3-components-jupyterhub.md",
    "L4_Deployment_OCP": "L4-deployment-ocp.md",
}

# Per-boundary L4 filenames (generated from deployment view data)
BOUNDARY_TO_FILENAME = {
    "Dremio": "L4-deployment-dremio.md",
    "MongoDB": "L4-deployment-mongodb.md",
    "Superset": "L4-deployment-superset.md",
    "Spark": "L4-deployment-spark.md",
    "Airflow": "L4-deployment-airflow.md",
    "JupyterHub": "L4-deployment-jupyterhub.md",
}

TYPE_ORDER = {
    "Person": 0,
    "Software System": 1,
    "Container": 2,
    "Component": 3,
    "Deployment Node": 4,
    "Container Instance": 5,
    "Software System Instance": 6,
}

TYPE_HEADINGS = {
    "Person": "Aktorzy",
    "Software System": "Systemy",
    "Container": "Kontenery",
    "Component": "Komponenty",
}


def load_workspace(path):
    with open(path) as f:
        return json.load(f)


def build_docs_index(model):
    """Build dict: element_id (str) -> list of documentation section content strings.

    Extracts !docs content from software systems and containers in the JSON export.
    """
    index = {}
    for system in model.get("softwareSystems", []):
        sections = system.get("documentation", {}).get("sections", [])
        if sections:
            contents = [s["content"] for s in sorted(sections, key=lambda s: s.get("order", 0))]
            index[str(system["id"])] = contents
        for container in system.get("containers", []):
            sections = container.get("documentation", {}).get("sections", [])
            if sections:
                contents = [s["content"] for s in sorted(sections, key=lambda s: s.get("order", 0))]
                index[str(container["id"])] = contents
    return index


def build_element_index(model):
    """Build flat dict: element_id (str) -> element_data."""
    index = {}

    for person in model.get("people", []):
        person["_type"] = "Person"
        index[str(person["id"])] = person

    for system in model.get("softwareSystems", []):
        system["_type"] = "Software System"
        index[str(system["id"])] = system

        for container in system.get("containers", []):
            container["_type"] = "Container"
            container["_parent"] = system["name"]
            index[str(container["id"])] = container

            for component in container.get("components", []):
                component["_type"] = "Component"
                component["_parent"] = container["name"]
                index[str(component["id"])] = component

    def index_nodes(nodes, parent_name=""):
        for node in nodes:
            node["_type"] = "Deployment Node"
            node["_parent"] = parent_name
            index[str(node["id"])] = node

            for instance in node.get("containerInstances", []):
                instance["_type"] = "Container Instance"
                instance["_parent"] = node["name"]
                index[str(instance["id"])] = instance

            for instance in node.get("softwareSystemInstances", []):
                instance["_type"] = "Software System Instance"
                instance["_parent"] = node["name"]
                index[str(instance["id"])] = instance

            index_nodes(node.get("children", []), node["name"])

    for env in model.get("deploymentNodes", []):
        index_nodes([env])

    return index


def build_relationship_index(model):
    """Collect all relationships from all elements into flat dict."""
    index = {}

    def collect(element):
        for rel in element.get("relationships", []):
            index[str(rel["id"])] = rel

    for person in model.get("people", []):
        collect(person)

    for system in model.get("softwareSystems", []):
        collect(system)
        for container in system.get("containers", []):
            collect(container)
            for component in container.get("components", []):
                collect(component)

    return index


def escape_md(text):
    """Escape pipe characters for markdown tables."""
    return text.replace("|", "\\|") if text else ""


def read_puml_file(puml_path):
    """Read a .puml file and return its content, or None if not found."""
    try:
        with open(puml_path) as f:
            return f.read()
    except FileNotFoundError:
        return None


def get_user_properties(elem):
    """Get non-structurizr properties from an element."""
    props = elem.get("properties", {})
    return {k: v for k, v in props.items() if not k.startswith("structurizr.")}


def generate_view_doc(view, view_type, elements, relationships, diagrams_dir, diagrams_rel, docs_index=None):
    """Generate markdown content for one view."""
    key = view["key"]
    title = view.get("title", key)
    description = view.get("description", "")

    lines = [
        "<!-- Wygenerowano automatycznie z workspace.dsl — NIE EDYTUJ RĘCZNIE -->",
        "<!-- Regeneracja: ./scripts/generate-diagrams.sh -->",
        "",
        f"# {title}",
        "",
    ]

    if description:
        lines += [f"> {description}", ""]

    # --- System introduction for systemContext views ---
    if view_type == "systemContext":
        system_id = str(view.get("softwareSystemId", ""))
        system_elem = elements.get(system_id)
        if system_elem:
            sys_desc = system_elem.get("description", "")
            if sys_desc:
                lines += ["## Przegląd", "", sys_desc, ""]
            sys_props = get_user_properties(system_elem)
            if sys_props:
                lines += ["| Właściwość | Wartość |", "|------------|--------|"]
                for k, v in sys_props.items():
                    lines.append(f"| {escape_md(k)} | {escape_md(v)} |")
                lines.append("")
            # Append !docs content for the software system
            if docs_index and system_id in docs_index:
                for content in docs_index[system_id]:
                    lines += [content.rstrip(), ""]

    # --- Container !docs for component views ---
    if view_type == "component" and docs_index:
        container_id = str(view.get("containerId", ""))
        if container_id in docs_index:
            for content in docs_index[container_id]:
                lines += [content.rstrip(), ""]

    # --- Embedded PlantUML diagram ---
    puml_name = f"structurizr-{key}.puml"
    puml_path = diagrams_dir / puml_name
    puml_content = read_puml_file(puml_path)

    if puml_content:
        lines += [
            "## Diagram architektury",
            "",
            f"![{title}]({diagrams_rel}/{puml_name.replace('.puml', '.svg')})",
            "",
            "<details>",
            "<summary>Źródło PlantUML</summary>",
            "",
            "```plantuml",
            puml_content.rstrip(),
            "```",
            "",
            "</details>",
            "",
        ]
    else:
        svg_name = f"structurizr-{key}.svg"
        lines += [f"![{title}]({diagrams_rel}/{svg_name})", ""]

    # Collect elements shown in this view
    view_elem_ids = {str(e["id"]) for e in view.get("elements", [])}
    view_elems = [elements[eid] for eid in view_elem_ids if eid in elements]
    view_elems.sort(
        key=lambda e: (TYPE_ORDER.get(e.get("_type", ""), 9), e.get("name", ""))
    )

    # --- Non-deployment views: elements as readable sections ---
    if view_elems and view_type != "deployment":
        current_type = None
        for elem in view_elems:
            etype = elem.get("_type", "")
            name = elem.get("name", "")
            desc = elem.get("description", "")
            tech = elem.get("technology", "")
            props = get_user_properties(elem)

            # Type group heading
            if etype != current_type:
                current_type = etype
                heading = TYPE_HEADINGS.get(etype, etype)
                lines += [f"## {heading}", ""]

            # Element heading
            if tech:
                lines.append(f"### {name}")
                lines.append("")
                lines.append(f"**Technologia:** {tech}")
            else:
                lines.append(f"### {name}")
            lines.append("")

            # Description as paragraph
            if desc:
                lines += [desc, ""]

            # Properties table
            if props:
                lines += ["| Właściwość | Wartość |", "|------------|--------|"]
                for k, v in props.items():
                    lines.append(f"| {escape_md(k)} | {escape_md(v)} |")
                lines.append("")

    # --- Deployment views: nodes as readable sections ---
    if view_type == "deployment" and view_elems:
        dep_nodes = [e for e in view_elems if e.get("_type") == "Deployment Node"]
        if dep_nodes:
            # Group by parent (namespace)
            namespaces = {}
            for node in dep_nodes:
                parent = node.get("_parent", "")
                namespaces.setdefault(parent, []).append(node)

            # Top-level nodes (namespaces themselves)
            top_level = namespaces.get("", [])
            for ns_node in sorted(top_level, key=lambda n: n.get("name", "")):
                ns_name = ns_node.get("name", "")
                ns_tech = ns_node.get("technology", "")
                lines += [f"## {ns_name}", ""]
                if ns_tech:
                    lines += [f"**Technologia:** {ns_tech}", ""]

                props = get_user_properties(ns_node)
                if props:
                    lines += ["| Właściwość | Wartość |", "|------------|--------|"]
                    for k, v in props.items():
                        lines.append(f"| {escape_md(k)} | {escape_md(v)} |")
                    lines.append("")

                # Child nodes under this namespace
                children = namespaces.get(ns_name, [])
                if children:
                    lines += [
                        "| Obciążenie | Typ |",
                        "|------------|-----|",
                    ]
                    for child in sorted(children, key=lambda n: n.get("name", "")):
                        cname = escape_md(child.get("name", ""))
                        ctech = escape_md(child.get("technology", ""))
                        lines.append(f"| {cname} | {ctech} |")
                    lines.append("")

    # --- Relationships ---
    view_rel_ids = {str(r["id"]) for r in view.get("relationships", [])}
    view_rels = [relationships[rid] for rid in view_rel_ids if rid in relationships]
    view_rels.sort(
        key=lambda r: elements.get(str(r.get("sourceId", "")), {}).get("name", "")
    )

    if view_rels:
        lines += ["## Relacje", ""]
        lines += [
            "| Od | Do | Opis | Technologia |",
            "|----|-----|------|-------------|",
        ]
        for rel in view_rels:
            src = elements.get(str(rel.get("sourceId", "")), {}).get("name", "?")
            dst = elements.get(str(rel.get("destinationId", "")), {}).get("name", "?")
            desc = escape_md(rel.get("description", ""))
            tech = escape_md(rel.get("technology", ""))
            lines.append(f"| {escape_md(src)} | {escape_md(dst)} | {desc} | {tech} |")
        lines.append("")

    return "\n".join(lines)


def read_extras_file(extras_dir, filename):
    """Read a companion extras file if it exists, return content or None."""
    extras_path = extras_dir / filename
    try:
        with open(extras_path) as f:
            return f.read().rstrip()
    except FileNotFoundError:
        return None


def generate_boundary_docs(elements, extras_dir):
    """Generate per-container-boundary L4 deployment docs from element index.

    Auto-generated content from DSL properties is merged with hand-maintained
    companion files from extras_dir (e.g., extras/L4-deployment-mongodb.md)
    for rich content like Mermaid diagrams and multi-column K8s object tables.
    """
    # Build parent -> children map for deployment nodes
    children_by_parent = {}
    for elem in elements.values():
        if elem.get("_type") == "Deployment Node":
            parent = elem.get("_parent", "")
            children_by_parent.setdefault(parent, []).append(elem)

    docs = {}

    # Find Container Boundary nodes at any depth
    for children in children_by_parent.values():
        for boundary in children:
            b_name = boundary.get("name", "")
            b_tech = boundary.get("technology", "")

            if b_tech != "Container Boundary":
                continue

            filename = BOUNDARY_TO_FILENAME.get(b_name)
            if not filename:
                continue

            ns_name = boundary.get("_parent", "unknown")

            lines = [
                "<!-- Wygenerowano automatycznie z workspace.dsl + extras/ — NIE EDYTUJ RĘCZNIE -->",
                "<!-- Właściwości DSL są generowane automatycznie; zawartość extras/ jest utrzymywana ręcznie -->",
                "<!-- Regeneracja: ./scripts/generate-diagrams.sh -->",
                "",
                f"# L4 - Wdrożenie: {b_name}",
                "",
                f"> Granica kontenera dla {b_name} w ramach {ns_name}.",
                "",
            ]

            # Extras content first (hand-maintained rich docs)
            extras_content = read_extras_file(extras_dir, filename)
            if extras_content:
                lines += [extras_content, ""]

            # Workspace-derived sections below
            props = get_user_properties(boundary)
            monitoring_props = {
                k: v for k, v in props.items() if k.startswith("Monitoring")
            }
            other_props = {
                k: v for k, v in props.items() if not k.startswith("Monitoring")
            }

            if monitoring_props:
                lines += ["## Monitorowanie", ""]
                lines += ["| Punkt końcowy | Wartość |", "|---------------|--------|"]
                for k, v in monitoring_props.items():
                    label = k.replace("Monitoring: ", "")
                    lines.append(f"| {escape_md(label)} | {escape_md(v)} |")
                lines.append("")

            if other_props:
                lines += ["## Właściwości", ""]
                lines += ["| Właściwość | Wartość |", "|------------|--------|"]
                for k, v in other_props.items():
                    lines.append(f"| {escape_md(k)} | {escape_md(v)} |")
                lines.append("")

            # Runtime units
            runtime_units = children_by_parent.get(b_name, [])
            lines += ["## Jednostki uruchomieniowe", ""]

            if runtime_units:
                for unit in sorted(runtime_units, key=lambda n: n.get("name", "")):
                    u_name = unit.get("name", "")
                    u_tech = unit.get("technology", "")
                    lines += [f"### {u_name}", ""]
                    if u_tech:
                        lines += [f"**Typ:** {u_tech}", ""]

                    u_props = get_user_properties(unit)
                    if u_props:
                        lines += ["| Właściwość | Wartość |", "|------------|--------|"]
                        for k, v in u_props.items():
                            lines.append(
                                f"| {escape_md(k)} | {escape_md(v)} |"
                            )
                        lines.append("")
                    else:
                        lines += ["*TODO: Dodaj szczegóły wdrożenia*", ""]
            else:
                lines += ["*TODO: Zdefiniuj jednostki uruchomieniowe*", ""]

            docs[filename] = "\n".join(lines)

    return docs


def main():
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <workspace.json> <output-dir> [diagrams-dir]")
        print()
        print("Generate markdown docs from Structurizr workspace JSON export.")
        print()
        print("Arguments:")
        print("  workspace.json  Exported JSON from structurizr-cli")
        print("  output-dir      Directory for generated markdown (e.g. levels/)")
        print("  diagrams-dir    Directory containing .puml files (e.g. diagrams/generated/)")
        print()
        print("Steps:")
        print("  1. structurizr-cli export -workspace workspace.dsl -format json -output /tmp")
        print(f"  2. python3 {sys.argv[0]} /tmp/structurizr-*.json levels/ diagrams/generated/")
        sys.exit(1)

    json_path = Path(sys.argv[1])
    output_dir = Path(sys.argv[2])
    output_dir.mkdir(parents=True, exist_ok=True)

    # Diagrams directory (for reading .puml files)
    if len(sys.argv) >= 4:
        diagrams_dir = Path(sys.argv[3])
    else:
        diagrams_dir = output_dir.parent / "diagrams" / "generated"

    workspace = load_workspace(json_path)
    model = workspace.get("model", {})
    views = workspace.get("views", {})

    elements = build_element_index(model)
    relationships = build_relationship_index(model)
    docs_index = build_docs_index(model)

    # Relative path from output_dir (levels/) to SVG subfolder
    # SVGs are copied to levels/svg/ by generate-diagrams.sh step 7
    diagrams_rel = "svg"

    generated = []

    for view_type, view_key in [
        ("systemContext", "systemContextViews"),
        ("container", "containerViews"),
        ("component", "componentViews"),
        ("deployment", "deploymentViews"),
    ]:
        for view in views.get(view_key, []):
            key = view["key"]
            filename = VIEW_KEY_TO_FILENAME.get(
                key, f"{key.lower().replace('_', '-')}.md"
            )

            doc = generate_view_doc(
                view, view_type, elements, relationships, diagrams_dir, diagrams_rel, docs_index
            )

            out_path = output_dir / filename
            with open(out_path, "w") as f:
                f.write(doc)

            generated.append((key, filename, view.get("title", key)))
            print(f"  Generated: {out_path}")

    # Generate per-boundary L4 deployment docs
    # Extras dir: hand-maintained companion files merged into generated output
    extras_dir = output_dir.parent / "extras"
    boundary_docs = generate_boundary_docs(elements, extras_dir)
    for filename, content in sorted(boundary_docs.items()):
        out_path = output_dir / filename
        with open(out_path, "w") as f:
            f.write(content)
        generated.append((filename, filename, f"L4 boundary: {filename}"))
        print(f"  Generated: {out_path}")

    print(f"\n  {len(generated)} documents generated in {output_dir}/")


if __name__ == "__main__":
    main()
