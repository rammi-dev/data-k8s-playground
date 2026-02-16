#!/usr/bin/env python3
"""Convert HIP CSV.zip files from S3 to Parquet, organized by table name.

Source structure:
  s3://dlh-source-data-lab/reporting/hip/in/<date>/  (e.g. 2024-06-13/)
    RBUS_ENERBIL5_20250516_K_20250716110858726.csv.ZIP
    PLA_BPKD_20250516_2_20250515174420841.csv.ZIP
    RBES_PARAMTECHZAS_20251214__20240612194246664.csv.zip

Table name = everything before the first _YYYYMMDD date segment.

Output:
  s3://dlh-lab/parquet/<TABLE_NAME>/<original_base>.parquet

Usage:
  ./hip_zip_to_parquet.py list                    # list all table types
  ./hip_zip_to_parquet.py convert RBUS_ENERBIL5   # convert one table
  ./hip_zip_to_parquet.py convert all             # convert all tables

Uses S3_ENDPOINT, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY env vars.
If not provided, defaults to https://localhost:9000 with minio/minio123 credentials.

Optional env vars:
  S3_SOURCE_BUCKET  (default: dlh-source-data-lab)
  S3_TARGET_BUCKET  (default: dlh-lab)
  S3_VERIFY_SSL     (default: false — set to "true" for verified SSL)
"""

import io
import os
import re
import sys
import zipfile
from collections import defaultdict

import polars as pl
import s3fs


DEFAULTS = {
    "S3_ENDPOINT": "https://localhost:9000",
    "AWS_ACCESS_KEY_ID": "minio",
    "AWS_SECRET_ACCESS_KEY": "minio123",
    "S3_SOURCE_BUCKET": "dlh-source-data-lab",
    "S3_TARGET_BUCKET": "dlh-lab",
    "S3_VERIFY_SSL": "false",
}

# Matches _YYYYMMDD (8 digits after underscore) to split table name from rest
TABLE_NAME_RE = re.compile(r"^(.+?)_\d{8}")


def env(var: str) -> str:
    return os.environ.get(var) or DEFAULTS[var]


def get_s3_fs() -> s3fs.S3FileSystem:
    verify_ssl = env("S3_VERIFY_SSL").lower() == "true"
    client_kwargs = {"endpoint_url": env("S3_ENDPOINT"), "verify": verify_ssl}
    return s3fs.S3FileSystem(
        key=env("AWS_ACCESS_KEY_ID"),
        secret=env("AWS_SECRET_ACCESS_KEY"),
        client_kwargs=client_kwargs,
    )


def extract_table_name(filename: str) -> str | None:
    """Extract table name from filename like RBUS_ENERBIL5_20250516_K_....csv.ZIP"""
    base = filename.split("/")[-1]
    m = TABLE_NAME_RE.match(base)
    return m.group(1) if m else None


def discover_zip_files(fs: s3fs.S3FileSystem, source_bucket: str) -> dict[str, list[str]]:
    """Scan all date folders and group zip files by table name.

    Returns: {table_name: [full_s3_path, ...]}
    """
    hip_prefix = f"{source_bucket}/reporting/hip/in"
    table_files: dict[str, list[str]] = defaultdict(list)

    try:
        date_folders = sorted(fs.ls(hip_prefix))
    except FileNotFoundError:
        print(f"Source path not found: s3://{hip_prefix}/")
        return {}

    for folder in date_folders:
        if not fs.isdir(folder):
            continue
        try:
            files = fs.ls(folder)
        except FileNotFoundError:
            continue

        for f in files:
            fname = f.split("/")[-1]
            if not fname.lower().endswith(".zip"):
                continue
            table = extract_table_name(fname)
            if table:
                table_files[table].append(f)

    return dict(table_files)


def read_csv_from_zip(fs: s3fs.S3FileSystem, zip_path: str) -> tuple[str, bytes] | None:
    """Download zip and extract the first CSV. Returns (filename, csv_bytes) or None."""
    fname = zip_path.split("/")[-1]
    try:
        with fs.open(zip_path, "rb") as f:
            with zipfile.ZipFile(io.BytesIO(f.read())) as zf:
                csv_names = [n for n in zf.namelist() if n.lower().endswith(".csv")]
                if not csv_names:
                    print(f"  SKIP {fname}: no CSV inside zip")
                    return None
                return fname, zf.read(csv_names[0])
    except Exception as e:
        print(f"  ERROR {fname}: {e}")
        return None


def collect_union_schema(
    fs: s3fs.S3FileSystem, zip_paths: list[str],
) -> list[str]:
    """Read headers from all zips to build the union of all column names (preserving order)."""
    seen: dict[str, int] = {}
    for zip_path in sorted(zip_paths):
        result = read_csv_from_zip(fs, zip_path)
        if result is None:
            continue
        _, csv_data = result
        # Ensure UTF-8 encoding
        try:
            csv_data.decode("utf-8")
        except UnicodeDecodeError:
            csv_data = csv_data.decode("latin-1").encode("utf-8")
        # Read just the header line
        header_line = csv_data.split(b"\n", 1)[0].decode("utf-8").strip()
        for col in header_line.split(";"):
            col = col.strip()
            if col and col not in seen:
                seen[col] = len(seen)
    return list(seen.keys())


def align_to_schema(df: pl.DataFrame, schema_cols: list[str]) -> pl.DataFrame:
    """Add missing columns as null and reorder to match the union schema."""
    for col in schema_cols:
        if col not in df.columns:
            df = df.with_columns(pl.lit(None).cast(pl.Utf8).alias(col))
    return df.select(schema_cols)


def split_good_and_bad_rows(csv_data: bytes) -> tuple[bytes, list[bytes]]:
    """Split CSV data into good rows (matching header field count) and bad rows.

    Returns (good_csv_bytes_with_header, list_of_bad_row_bytes).
    """
    lines = csv_data.split(b"\n")
    if not lines:
        return b"", []

    header = lines[0]
    expected_fields = header.count(b";") + 1

    good_lines = [header]
    bad_lines = []

    for line in lines[1:]:
        stripped = line.rstrip(b"\r")
        if not stripped:
            continue
        field_count = stripped.count(b";") + 1
        if field_count == expected_fields:
            good_lines.append(line)
        else:
            bad_lines.append(line)

    return b"\n".join(good_lines), bad_lines


def convert_table(
    fs: s3fs.S3FileSystem,
    table_name: str,
    zip_paths: list[str],
    target_bucket: str,
) -> int:
    """Convert all zip files for a given table to parquet with unified schema."""
    parquet_prefix = f"{target_bucket}/parquet/{table_name}"
    error_prefix = f"{target_bucket}/parquet/{table_name}/errors"
    sorted_paths = sorted(zip_paths)

    # Pass 1: build union schema from all file headers
    print("  Collecting union schema...")
    schema_cols = collect_union_schema(fs, sorted_paths)
    if not schema_cols:
        print("  No valid CSV headers found.")
        return 0
    print(f"  Union schema: {len(schema_cols)} columns")

    # Pass 2: convert each file with the unified schema
    count = 0
    total_errors = 0
    for zip_path in sorted_paths:
        fname = zip_path.split("/")[-1]
        base = re.sub(r"\.csv\.zip$", "", fname, flags=re.IGNORECASE)

        result = read_csv_from_zip(fs, zip_path)
        if result is None:
            continue
        _, csv_data = result

        # Ensure UTF-8 encoding (source files may be Latin-1/Windows-1252)
        try:
            csv_data.decode("utf-8")
        except UnicodeDecodeError:
            csv_data = csv_data.decode("latin-1").encode("utf-8")

        # Separate good rows from ragged rows
        good_csv, bad_lines = split_good_and_bad_rows(csv_data)

        # Write bad rows to error file
        if bad_lines:
            error_path = f"{error_prefix}/{base}.csv"
            header_line = csv_data.split(b"\n", 1)[0]
            error_content = header_line + b"\n" + b"\n".join(bad_lines)
            with fs.open(error_path, "wb") as f:
                f.write(error_content)
            print(f"  WARN {fname}: {len(bad_lines)} ragged row(s) -> errors/{base}.csv")
            total_errors += len(bad_lines)

        if good_csv.count(b"\n") < 1:
            print(f"  SKIP {fname}: no valid data rows")
            continue

        try:
            df = pl.read_csv(
                io.BytesIO(good_csv),
                separator=";",
                infer_schema_length=0,
                quote_char=None,
            )
        except Exception as e:
            print(f"  ERROR reading CSV from {fname}: {e}")
            continue

        df = align_to_schema(df, schema_cols)

        parquet_buf = io.BytesIO()
        df.write_parquet(parquet_buf)
        parquet_buf.seek(0)

        parquet_path = f"{parquet_prefix}/{base}.parquet"
        with fs.open(parquet_path, "wb") as f:
            f.write(parquet_buf.read())

        print(f"  {fname} -> {base}.parquet ({len(df)} rows, {len(df.columns)} cols)")
        count += 1

    if total_errors:
        print(f"  Total ragged rows sent to errors/: {total_errors}")
    return count


def cmd_list(fs: s3fs.S3FileSystem, source_bucket: str, target_bucket: str):
    """List all discovered table types with file counts and target paths."""
    print(f"Scanning s3://{source_bucket}/reporting/hip/in/ ...")
    table_files = discover_zip_files(fs, source_bucket)

    if not table_files:
        print("No zip files found.")
        return

    print(f"\nFound {len(table_files)} table type(s):\n")
    for table in sorted(table_files):
        target = f"s3://{target_bucket}/parquet/{table}/"
        print(f"  {table:40s} {len(table_files[table]):>5} file(s)  -> {target}")
    print(f"\nTotal: {sum(len(v) for v in table_files.values())} zip file(s)")


def cmd_convert(fs: s3fs.S3FileSystem, source_bucket: str, target_bucket: str, table_arg: str):
    """Convert zip files for one or all tables to parquet."""
    print(f"Scanning s3://{source_bucket}/reporting/hip/in/ ...")
    table_files = discover_zip_files(fs, source_bucket)

    if not table_files:
        print("No zip files found.")
        return

    if table_arg == "all":
        tables = sorted(table_files.keys())
    else:
        if table_arg not in table_files:
            print(f"Table '{table_arg}' not found. Available tables:")
            for t in sorted(table_files):
                print(f"  {t}")
            sys.exit(1)
        tables = [table_arg]

    total = 0
    for table in tables:
        zips = table_files[table]
        print(f"\n[{table}] ({len(zips)} zip file(s)):")
        converted = convert_table(fs, table, zips, target_bucket)
        total += converted

    print(f"\nDone: {total} file(s) converted to parquet")


def main():
    if len(sys.argv) < 2:
        print("Usage:")
        print("  python hip_zip_to_parquet.py list                    # list all table types")
        print("  python hip_zip_to_parquet.py convert <TABLE|all>     # convert to parquet")
        sys.exit(1)

    command = sys.argv[1]

    used_defaults = [k for k in DEFAULTS if not os.environ.get(k)]
    if used_defaults:
        print(f"Using defaults for: {', '.join(used_defaults)}")

    fs = get_s3_fs()
    source_bucket = env("S3_SOURCE_BUCKET")
    target_bucket = env("S3_TARGET_BUCKET")

    if command == "list":
        cmd_list(fs, source_bucket, target_bucket)
    elif command == "convert":
        if len(sys.argv) != 3:
            print("Usage: python hip_zip_to_parquet.py convert <TABLE_NAME|all>")
            sys.exit(1)
        cmd_convert(fs, source_bucket, target_bucket, sys.argv[2])
    else:
        print(f"Unknown command: {command}")
        print("Use 'list' or 'convert'")
        sys.exit(1)


if __name__ == "__main__":
    main()
