#!/usr/bin/env python3
"""Generate INSERT SQL statements from the mapping CSV (tabela_mapujaca_actual.csv).

Reads the mapping CSV and produces Iceberg-compatible INSERT INTO statements
with SCD Type 2 historization via LEAD window function.

Assumes full rebuild: target table is truncated before loading.

Pattern per destination table:
  TRUNCATE TABLE {catalog}.normalized.{dest_table};

  INSERT INTO {catalog}.normalized.{dest_table}
  SELECT {mapped_cols},
         src._czas_z_ekstraktu,
         CURRENT_TIMESTAMP AS _czas_aktualizacji,
         src._czas_z_ekstraktu AS _aktualne_od,
         LEAD(src._czas_z_ekstraktu) OVER (
             PARTITION BY {pk_cols}
             ORDER BY src._czas_z_ekstraktu
         ) AS _aktualne_do
  FROM {catalog}.raw.{source_table} src
  [LEFT JOIN nessie.normalized.doba ...]
  [LEFT JOIN nessie.normalized.okres_w_dobie ...]
  [WHERE ...]

Usage:
  python generate_merge_sql.py                           # all tables
  python generate_merge_sql.py --table dokument_zru      # single destination table
  python generate_merge_sql.py --output output.sql       # write to file
  python generate_merge_sql.py --raw-extracts path/to/raw_extracts_definitions.py
  python generate_merge_sql.py --ddl-dir path/to/catalog/normalized/  # DDL-aware tech cols
"""

import argparse
import ast
import csv
import os
import re
import sys
from collections import defaultdict

CATALOG = "nessie"
RAW_SCHEMA = "raw"
NORM_SCHEMA = "normalized"

# CSV column names (Polish headers from the mapping file)
COL_SOURCE_TAB = "Tabela zrodlowa"
COL_DEST_TAB = "Tabela docelowa"
COL_SOURCE_COL = "Kolumna w tab zrodlowej"
COL_DEST_COL = "Kolumna w tab docelowej"
COL_STEREOTYPE = "STEREOTYPE"
COL_TYPE = "TYPE"
COL_PRECISION = "PRECISION"
COL_SCALE = "SCALE"
COL_PRIMARY_KEY = "PRIMARY_KEY"
COL_WARUNKI = "WARUNKI"
COL_ZRODLO = "ZRODLO"

TECH_COLUMNS = ["_czas_z_ekstraktu", "_czas_aktualizacji", "_aktualne_od"]
HIST_COLUMN = "_aktualne_do"

# Timestamp source columns that can resolve to okres_w_dobie_id
TS_SOURCE_COLS = {"udt_do", "utctime", "utc_do"}

# Ziarno → okres rynku mapping (from utils.py get_ziarno_and_okres_ids)
ZIARNO_TO_OKRES = {
    "PT15M": "OREB",
    "PT5M": "OPCR",
    "PT60M": "ONMB",
}


def parse_mapping_csv(filename):
    """Parse the mapping CSV and return rows as list of dicts."""
    rows = []
    with open(filename, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f, delimiter=";")
        for row in reader:
            if row.get(COL_DEST_TAB):
                rows.append(row)
    return rows


def group_mappings(rows):
    """Group rows by (destination_table, source_table).

    Returns dict: dest_table -> list of (source_table, [mapping_rows])
    """
    pair_map = defaultdict(list)
    for row in rows:
        if row.get(COL_ZRODLO, "").strip().upper() != "RAW":
            continue
        dest = row[COL_DEST_TAB].strip()
        src = row[COL_SOURCE_TAB].strip()
        pair_map[(dest, src)].append(row)

    dest_map = defaultdict(list)
    for (dest, src), mapping_rows in pair_map.items():
        dest_map[dest].append((src, mapping_rows))

    return dest_map


def get_target_columns(dest_map, dest_table, ddl_schemas=None):
    """Collect all target columns for a destination table across all sources."""
    all_cols = set()
    for src, mapping_rows in dest_map[dest_table]:
        for row in mapping_rows:
            all_cols.add(row[COL_DEST_COL].strip())

    # Add tech columns based on DDL (or all by default)
    if ddl_schemas and dest_table in ddl_schemas:
        schema_cols = ddl_schemas[dest_table]
        for tc in TECH_COLUMNS:
            if tc in schema_cols:
                all_cols.add(tc)
        if HIST_COLUMN in schema_cols:
            all_cols.add(HIST_COLUMN)
    elif ddl_schemas is not None:
        # DDL dir provided but no DDL for this table — only basic tech columns
        all_cols.add("_czas_z_ekstraktu")
        all_cols.add("_czas_aktualizacji")
    else:
        # No --ddl-dir — backward compatible, all tech columns
        all_cols.update(TECH_COLUMNS)
        all_cols.add(HIST_COLUMN)

    return all_cols


def parse_raw_extracts_definitions(filename):
    """Parse raw_extracts_definitions.py and return raw_table_name -> id_cols dict.

    Extracts the extract_table_name_mapping dict from the Python source,
    then builds a lookup: raw table name -> list of PK column names.
    Empty id_cols ([""] or []) are treated as no PK.
    """
    with open(filename, "r", encoding="utf-8") as f:
        source = f.read()

    # Extract just the dict assignment
    match = re.search(
        r"extract_table_name_mapping\s*=\s*(\{.*?\n\})",
        source,
        re.DOTALL,
    )
    if not match:
        print("WARNING: Could not parse extract_table_name_mapping", file=sys.stderr)
        return {}

    try:
        mapping = ast.literal_eval(match.group(1))
    except (SyntaxError, ValueError) as e:
        print(f"WARNING: Failed to eval extract_table_name_mapping: {e}", file=sys.stderr)
        return {}

    raw_pks = {}
    for _extract_name, info in mapping.items():
        table_tuple = info.get("table", ())
        id_cols = info.get("id_cols", [])
        if len(table_tuple) >= 3:
            raw_table = table_tuple[2]
            # Filter out empty strings
            valid_cols = [c for c in id_cols if c.strip()]
            if valid_cols:
                raw_pks[raw_table] = valid_cols
    return raw_pks


def parse_ddl_schemas(ddl_dir):
    """Parse all .sql DDL files in a directory and extract column names per table.

    Returns dict: table_name -> set of column names.
    """
    schemas = {}
    for filename in sorted(os.listdir(ddl_dir)):
        if not filename.endswith(".sql"):
            continue
        filepath = os.path.join(ddl_dir, filename)
        with open(filepath, "r", encoding="utf-8") as f:
            content = f.read()

        # Extract table name from CREATE TABLE line
        table_match = re.search(
            r"CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?(?:\w+\.)*(\w+)\s*\(",
            content,
            re.IGNORECASE,
        )
        if not table_match:
            continue
        table_name = table_match.group(1)

        # Extract column names from column definitions
        columns = set()
        in_columns = False
        for line in content.split("\n"):
            stripped = line.strip()
            if table_match.group(0) in line or stripped.startswith("CREATE"):
                in_columns = True
                continue
            if not in_columns:
                continue
            if stripped.startswith(")") or stripped.upper().startswith("PARTITION"):
                break
            # Match column: optional quotes, column name, then type keyword
            col_match = re.match(r'\s*"?(\w+)"?\s+\w+', stripped)
            if col_match:
                columns.add(col_match.group(1).lower())

        if columns:
            schemas[table_name] = columns

    return schemas


def resolve_pk_columns(source_table, mapping_rows, raw_pks):
    """Determine PK columns for PARTITION BY.

    Returns (pk_cols_normalized, pk_source) where pk_source is 'raw_extracts' or 'mapping_csv'.
    Prefers raw_extracts_definitions PKs (mapped to normalized names) over mapping CSV.
    """
    # Build src->dst column name mapping
    src_to_dst = {}
    for row in mapping_rows:
        src_col = row[COL_SOURCE_COL].strip()
        dst_col = row[COL_DEST_COL].strip()
        src_to_dst[src_col] = dst_col

    # Try raw_extracts first
    if raw_pks and source_table in raw_pks:
        raw_pk_cols = raw_pks[source_table]
        mapped_pks = []
        for raw_col in raw_pk_cols:
            if raw_col in src_to_dst:
                mapped_pks.append(src_to_dst[raw_col])
            else:
                # PK column exists in raw but isn't mapped to normalized
                # Use the raw name directly (it might be the same)
                mapped_pks.append(raw_col)
        if mapped_pks:
            return mapped_pks, "raw_extracts"

    # Fall back to mapping CSV PRIMARY_KEY=1
    csv_pks = []
    for row in mapping_rows:
        if row.get(COL_PRIMARY_KEY, "0").strip() == "1":
            csv_pks.append(row[COL_DEST_COL].strip())
    if csv_pks:
        return csv_pks, "mapping_csv"

    return [], "none"


def detect_okres_lookup(mapping_rows):
    """Detect if this source->dest pair needs okres_w_dobie_id lookup.

    Returns (needs_lookup, ts_col, has_ziarno, ziarno_col) where:
    - needs_lookup: True if okres_w_dobie_id is a dest column from a timestamp source
    - ts_col: the source timestamp column name (udt_do, utctime, etc.)
    - has_ziarno: True if source has ziarno_cz or ziarno column
    - ziarno_col: the ziarno column name
    """
    ts_col = None
    needs_lookup = False
    has_ziarno = False
    ziarno_col = None

    all_src_cols = set()
    for row in mapping_rows:
        src = row[COL_SOURCE_COL].strip()
        dst = row[COL_DEST_COL].strip()
        all_src_cols.add(src)

        if dst == "okres_w_dobie_id" and src in TS_SOURCE_COLS:
            needs_lookup = True
            ts_col = src

    # Check for ziarno column in mapped sources
    if "ziarno_cz" in all_src_cols:
        has_ziarno = True
        ziarno_col = "ziarno_cz"
    elif "ziarno" in all_src_cols:
        has_ziarno = True
        ziarno_col = "ziarno"
    elif needs_lookup:
        # ziarno_cz is not in the mapping CSV (it's a raw lookup column, not mapped
        # to any target). All raw tables with udt_do/utctime that need okres_w_dobie_id
        # also have ziarno_cz. Default to it for correct filtering.
        has_ziarno = True
        ziarno_col = "ziarno_cz"

    return needs_lookup, ts_col, has_ziarno, ziarno_col


def detect_doba_pl_from_lookup(mapping_rows, needs_okres_lookup):
    """Detect if doba_pl should be derived from the okres lookup.

    Returns True if:
    - okres_w_dobie JOIN is present
    - doba_pl is a destination column mapped from 'doba' (a date column)
    """
    if not needs_okres_lookup:
        return False

    for row in mapping_rows:
        src = row[COL_SOURCE_COL].strip()
        dst = row[COL_DEST_COL].strip()
        if dst == "doba_pl" and src == "doba":
            return True
    return False


def generate_insert_sql(dest_table, source_table, mapping_rows, all_target_cols,
                        raw_pks=None, ddl_schemas=None, catalog=CATALOG):
    """Generate INSERT INTO with optional LEAD historization for a (source, dest) pair.

    When ddl_schemas is provided, tech columns (_aktualne_od/_aktualne_do) are only
    emitted if they exist in the target table's DDL schema.
    """
    lines = []

    # Collect column mappings
    col_mappings = []  # (source_col, dest_col, type, stereotype)
    where_conditions = set()

    for row in mapping_rows:
        src_col = row[COL_SOURCE_COL].strip()
        dst_col = row[COL_DEST_COL].strip()
        col_type = row.get(COL_TYPE, "").strip()
        stereotype = row.get(COL_STEREOTYPE, "").strip()
        warunki = row.get(COL_WARUNKI, "").strip()

        col_mappings.append((src_col, dst_col, col_type, stereotype))

        if warunki:
            cond = warunki.strip()
            if cond.lower().startswith("where "):
                cond = cond[6:]
            where_conditions.add(cond)

    # Resolve PKs
    pk_cols, pk_source = resolve_pk_columns(source_table, mapping_rows, raw_pks)

    # Detect okres_w_dobie lookup need
    needs_okres_lookup, ts_col, has_ziarno, ziarno_col = detect_okres_lookup(mapping_rows)

    # Detect doba_pl derivation from lookup
    doba_pl_from_lookup = detect_doba_pl_from_lookup(mapping_rows, needs_okres_lookup)

    # Determine which tech columns to emit based on DDL
    if ddl_schemas and dest_table in ddl_schemas:
        schema_cols = ddl_schemas[dest_table]
        has_czas_z_ekstraktu = "_czas_z_ekstraktu" in schema_cols
        has_czas_aktualizacji = "_czas_aktualizacji" in schema_cols
        has_aktualne_od = "_aktualne_od" in schema_cols
        has_aktualne_do = "_aktualne_do" in schema_cols
        ddl_status = "matched"
    elif ddl_schemas is not None:
        # DDL dir provided but no DDL for this table — no SCD columns
        has_czas_z_ekstraktu = True
        has_czas_aktualizacji = True
        has_aktualne_od = False
        has_aktualne_do = False
        ddl_status = "no DDL"
    else:
        # No --ddl-dir provided — backward compatible, all tech columns
        has_czas_z_ekstraktu = True
        has_czas_aktualizacji = True
        has_aktualne_od = True
        has_aktualne_do = True
        ddl_status = "not checked"

    # Build list of tech columns that will actually be emitted
    active_tech_cols = set()
    if has_czas_z_ekstraktu:
        active_tech_cols.add("_czas_z_ekstraktu")
    if has_czas_aktualizacji:
        active_tech_cols.add("_czas_aktualizacji")
    if has_aktualne_od:
        active_tech_cols.add("_aktualne_od")
    if has_aktualne_do:
        active_tech_cols.add("_aktualne_do")

    # Determine mapped target columns and missing ones
    mapped_targets = set()
    for _, dst_col, _, _ in col_mappings:
        mapped_targets.add(dst_col)
    mapped_targets.update(active_tech_cols)

    missing_cols = sorted(all_target_cols - mapped_targets)

    # Group by source col to detect 1:N mappings
    src_to_dests = defaultdict(list)
    for src_col, dst_col, col_type, stereotype in col_mappings:
        src_to_dests[src_col].append((dst_col, col_type, stereotype))

    # Build SELECT columns
    select_parts = []
    seen_dst_cols = set()

    for src_col, dests in src_to_dests.items():
        for dst_col, col_type, stereotype in dests:
            if dst_col in seen_dst_cols:
                continue
            seen_dst_cols.add(dst_col)

            if dst_col == "okres_w_dobie_id" and needs_okres_lookup:
                select_parts.append("        owd.id AS okres_w_dobie_id")
            elif dst_col == "okres_w_dobie_id":
                # No lookup available, fallback to NULL
                select_parts.append(
                    f"        -- okres_w_dobie_id: no timestamp source detected for lookup\n"
                    f"        NULL AS {dst_col}"
                )
            elif dst_col == "doba_pl" and doba_pl_from_lookup:
                select_parts.append(
                    "        CASE WHEN owd.zmiana_doby_lokalnej = 1\n"
                    "             THEN DATE_ADD(d.doba_utc, 1)\n"
                    "             ELSE d.doba_utc\n"
                    "        END AS doba_pl"
                )
            elif dst_col == "czas_do_utc" and src_col in TS_SOURCE_COLS:
                select_parts.append(f"        CAST(src.{src_col} AS TIMESTAMP) AS {dst_col}")
            elif src_col == dst_col:
                select_parts.append(f"        src.{src_col}")
            else:
                select_parts.append(f"        src.{src_col} AS {dst_col}")

    # Tech columns (conditional on DDL schema)
    if has_czas_z_ekstraktu:
        select_parts.append("        src._czas_z_ekstraktu")
    if has_czas_aktualizacji:
        select_parts.append("        CURRENT_TIMESTAMP AS _czas_aktualizacji")
    if has_aktualne_od:
        select_parts.append("        src._czas_z_ekstraktu AS _aktualne_od")

    # Historization: LEAD to compute validity end date (only for SCD tables)
    if has_aktualne_do:
        if pk_cols:
            partition_by = ", ".join(pk_cols)
            select_parts.append(
                f"        LEAD(src._czas_z_ekstraktu) OVER (\n"
                f"            PARTITION BY {partition_by}\n"
                f"            ORDER BY src._czas_z_ekstraktu\n"
                f"        ) AS {HIST_COLUMN}"
            )
        else:
            select_parts.append(f"        NULL AS {HIST_COLUMN}")

    # NULLs for missing target columns (skip tech columns we're already emitting)
    for mc in missing_cols:
        if mc not in active_tech_cols:
            select_parts.append(f"        NULL AS {mc}")

    # Build FROM clause with optional JOINs
    from_parts = [f"FROM {catalog}.{RAW_SCHEMA}.{source_table} src"]

    if needs_okres_lookup:
        from_parts.append(
            f"LEFT JOIN {catalog}.{NORM_SCHEMA}.doba d\n"
            f"    ON CAST(src.{ts_col} AS DATE) = d.doba_utc"
        )
        if has_ziarno:
            ziarno_case = " ".join(
                f"WHEN '{z}' THEN '{o}'" for z, o in ZIARNO_TO_OKRES.items()
            )
            from_parts.append(
                f"LEFT JOIN {catalog}.{NORM_SCHEMA}.okres_w_dobie owd\n"
                f"    ON DATE_FORMAT(src.{ts_col}, 'HH:mm') = owd.czas_do_utc\n"
                f"   AND d.typ_doby_kod = owd.typ_doby_kod\n"
                f"   AND owd.ziarno_czasu_kod = src.{ziarno_col}\n"
                f"   AND owd.okres_rb_kod = CASE src.{ziarno_col} {ziarno_case} END"
            )
        else:
            from_parts.append(
                f"LEFT JOIN {catalog}.{NORM_SCHEMA}.okres_w_dobie owd\n"
                f"    ON DATE_FORMAT(src.{ts_col}, 'HH:mm') = owd.czas_do_utc\n"
                f"   AND d.typ_doby_kod = owd.typ_doby_kod"
            )

    # WHERE clause
    where_sql = ""
    if where_conditions:
        where_sql = "\nWHERE " + "\n  AND ".join(sorted(where_conditions))

    # Assemble INSERT INTO
    lines.append(f"-- Source: {catalog}.{RAW_SCHEMA}.{source_table}")
    lines.append(f"-- Target: {catalog}.{NORM_SCHEMA}.{dest_table}")
    if ddl_schemas is not None:
        tech_list = sorted(active_tech_cols) if active_tech_cols else ["none"]
        lines.append(f"-- DDL: {ddl_status} — tech cols: {', '.join(tech_list)}")
    if pk_cols and has_aktualne_do:
        lines.append(f"-- PK ({pk_source}): {', '.join(pk_cols)}")
        lines.append(f"-- Historization: LEAD(_czas_z_ekstraktu) OVER (PARTITION BY PK ORDER BY _czas_z_ekstraktu)")
    elif pk_cols:
        lines.append(f"-- PK ({pk_source}): {', '.join(pk_cols)}")
        lines.append(f"-- Historization: none (DDL has no _aktualne_do)")
    else:
        lines.append("-- PK: none defined")
    if needs_okres_lookup:
        lines.append(f"-- Lookup: okres_w_dobie via {ts_col} -> doba + okres_w_dobie JOIN")
    lines.append(f"INSERT INTO {catalog}.{NORM_SCHEMA}.{dest_table}")
    lines.append("SELECT")
    lines.append(",\n".join(select_parts))
    lines.append("\n".join(from_parts) + where_sql + ";")

    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description="Generate INSERT SQL from mapping CSV")
    parser.add_argument("--csv", default="tabela_mapujaca_actual.csv",
                        help="Path to mapping CSV (default: tabela_mapujaca_actual.csv)")
    parser.add_argument("--table", default=None,
                        help="Generate only for this destination table")
    parser.add_argument("--output", default=None,
                        help="Output file (default: stdout)")
    parser.add_argument("--catalog", default=CATALOG,
                        help=f"Catalog name (default: {CATALOG})")
    parser.add_argument("--raw-extracts", default=None,
                        help="Path to raw_extracts_definitions.py for PK enrichment")
    parser.add_argument("--ddl-dir", default=None,
                        help="Path to catalog/normalized/ DDL directory for schema-aware tech columns")
    args = parser.parse_args()

    catalog = args.catalog

    rows = parse_mapping_csv(args.csv)
    dest_map = group_mappings(rows)

    # Parse raw_extracts for PK enrichment
    raw_pks = {}
    if args.raw_extracts:
        raw_pks = parse_raw_extracts_definitions(args.raw_extracts)
        if raw_pks:
            print(f"Loaded PKs for {len(raw_pks)} raw tables from {args.raw_extracts}",
                  file=sys.stderr)

    # Parse DDL schemas for conditional tech columns
    ddl_schemas = None
    if args.ddl_dir:
        ddl_schemas = parse_ddl_schemas(args.ddl_dir)
        print(f"Loaded DDL schemas for {len(ddl_schemas)} tables from {args.ddl_dir}",
              file=sys.stderr)

    if args.table:
        if args.table not in dest_map:
            print(f"ERROR: destination table '{args.table}' not found in mapping CSV", file=sys.stderr)
            print(f"Available tables: {', '.join(sorted(dest_map.keys()))}", file=sys.stderr)
            sys.exit(1)
        tables_to_process = [args.table]
    else:
        tables_to_process = sorted(dest_map.keys())

    output_lines = []
    output_lines.append("-- =============================================================================")
    output_lines.append("-- Auto-generated INSERT SQL from tabela_mapujaca_actual.csv")
    output_lines.append(f"-- Catalog: {catalog}")
    output_lines.append(f"-- Tables: {len(tables_to_process)}")
    if raw_pks:
        output_lines.append(f"-- PK source: raw_extracts_definitions.py ({len(raw_pks)} tables with PKs)")
    if ddl_schemas is not None:
        output_lines.append(f"-- DDL schemas: {len(ddl_schemas)} tables loaded (tech columns conditional on DDL)")
    output_lines.append("-- =============================================================================")
    output_lines.append("-- Pattern: TRUNCATE + INSERT")
    output_lines.append("-- SCD columns (_aktualne_od/_aktualne_do with LEAD) only when present in DDL")
    output_lines.append("-- Tech columns (when DDL confirms):")
    output_lines.append("--   _czas_z_ekstraktu  = preserved from raw extract")
    output_lines.append("--   _czas_aktualizacji = CURRENT_TIMESTAMP (load time)")
    output_lines.append("--   _aktualne_od       = _czas_z_ekstraktu (validity start)")
    output_lines.append(f"--   {HIST_COLUMN}       = LEAD(_czas_z_ekstraktu) OVER (PK, _czas_z_ekstraktu)")
    output_lines.append("--     NULL = current/open record, non-NULL = closed (superseded by next extract)")
    output_lines.append("-- Lookups:")
    output_lines.append("--   okres_w_dobie_id resolved via JOIN doba + okres_w_dobie (when applicable)")
    output_lines.append("--   doba_pl derived from doba_utc + zmiana_doby_lokalnej (when lookup active)")
    output_lines.append("-- =============================================================================")
    output_lines.append("")

    for dest_table in tables_to_process:
        all_target_cols = get_target_columns(dest_map, dest_table, ddl_schemas)
        source_pairs = dest_map[dest_table]

        output_lines.append(f"-- {'=' * 77}")
        output_lines.append(f"-- {dest_table}")
        output_lines.append(f"--   Source tables: {', '.join(src for src, _ in source_pairs)}")
        output_lines.append(f"-- {'=' * 77}")
        output_lines.append("")

        # Truncate before loading
        output_lines.append(f"TRUNCATE TABLE {catalog}.{NORM_SCHEMA}.{dest_table};")
        output_lines.append("")

        for i, (source_table, mapping_rows) in enumerate(source_pairs):
            if i > 0:
                output_lines.append("")
            output_lines.append(f"-- [{i+1}/{len(source_pairs)}] {source_table} -> {dest_table}")
            output_lines.append(generate_insert_sql(
                dest_table, source_table, mapping_rows, all_target_cols,
                raw_pks=raw_pks, ddl_schemas=ddl_schemas, catalog=catalog
            ))
            output_lines.append("")

    result = "\n".join(output_lines)

    if args.output:
        with open(args.output, "w", encoding="utf-8") as f:
            f.write(result)
        print(f"Written to {args.output} ({len(tables_to_process)} tables)", file=sys.stderr)
    else:
        print(result)


if __name__ == "__main__":
    main()
