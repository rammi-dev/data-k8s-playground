"""Ingest CSV files into an Iceberg table with schema evolution.

Reads all CSV files, unions their schemas (handling column renames, additions,
and deletions), and writes a single combined table to Iceberg.

Supports two modes:
  - S3 mode: set S3_ENDPOINT, S3_BUCKET, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY
  - Local mode: falls back to local filesystem if S3 env vars are not set
"""

import glob
import os
from pathlib import Path

import polars as pl
import pyarrow as pa
from pyiceberg.catalog.sql import SqlCatalog
from pyiceberg.schema import Schema
from pyiceberg.types import (
    IntegerType,
    LongType,
    StringType,
    NestedField,
)

SCRIPT_DIR = Path(__file__).parent.resolve()
CSV_DIR = SCRIPT_DIR / "source" / "csv"

NAMESPACE = "default"
TABLE_NAME = "employees"


def get_s3_config() -> dict | None:
    """Return S3 config from env vars, or None for local mode."""
    endpoint = os.environ.get("S3_ENDPOINT")
    bucket = os.environ.get("S3_BUCKET")
    access_key = os.environ.get("AWS_ACCESS_KEY_ID")
    secret_key = os.environ.get("AWS_SECRET_ACCESS_KEY")

    if all([endpoint, bucket, access_key, secret_key]):
        return {
            "endpoint": endpoint,
            "bucket": bucket,
            "access_key": access_key,
            "secret_key": secret_key,
        }
    return None


def create_catalog(s3_config: dict | None) -> SqlCatalog:
    """Create an Iceberg catalog. S3 warehouse if config provided, else local."""
    catalog_db = SCRIPT_DIR / "output" / "catalog.db"
    catalog_db.parent.mkdir(parents=True, exist_ok=True)

    if s3_config:
        warehouse = f"s3://{s3_config['bucket']}/warehouse"
        catalog = SqlCatalog(
            "local",
            **{
                "uri": f"sqlite:///{catalog_db}",
                "warehouse": warehouse,
                "s3.endpoint": s3_config["endpoint"],
                "s3.access-key-id": s3_config["access_key"],
                "s3.secret-access-key": s3_config["secret_key"],
                "s3.region": "us-east-1",
            },
        )
    else:
        warehouse_dir = SCRIPT_DIR / "output" / "warehouse"
        warehouse_dir.mkdir(parents=True, exist_ok=True)
        catalog = SqlCatalog(
            "local",
            **{
                "uri": f"sqlite:///{catalog_db}",
                "warehouse": str(warehouse_dir),
            },
        )

    try:
        catalog.create_namespace(NAMESPACE)
    except Exception:
        pass  # Namespace already exists
    return catalog


def read_csvs_from_s3(s3_config: dict) -> list[pl.DataFrame]:
    """Read all CSV files from S3 bucket csv/ prefix."""
    import s3fs

    fs = s3fs.S3FileSystem(
        key=s3_config["access_key"],
        secret=s3_config["secret_key"],
        endpoint_url=s3_config["endpoint"],
    )

    bucket = s3_config["bucket"]
    csv_files = sorted(fs.glob(f"{bucket}/source/csv/*.csv"))
    if not csv_files:
        print(f"No CSV files found in s3://{bucket}/source/csv/")
        return []

    frames = []
    for s3_path in csv_files:
        filename = s3_path.split("/")[-1]
        with fs.open(s3_path, "rb") as f:
            df = pl.read_csv(f)
        print(f"\n  {filename}: {df.columns} ({len(df)} rows)")
        df = df.cast({col: pl.Utf8 for col in df.columns})
        frames.append(df)
    return frames


def read_csvs_from_local() -> list[pl.DataFrame]:
    """Read all CSV files from local csv/ directory."""
    csv_files = sorted(glob.glob(str(CSV_DIR / "*.csv")))
    if not csv_files:
        print(f"No CSV files found in {CSV_DIR}")
        return []

    frames = []
    for csv_path in csv_files:
        df = pl.read_csv(csv_path)
        print(f"\n  {Path(csv_path).name}: {df.columns} ({len(df)} rows)")
        df = df.cast({col: pl.Utf8 for col in df.columns})
        frames.append(df)
    return frames


def iceberg_schema_from_arrow(arrow_schema: pa.Schema) -> Schema:
    """Convert a PyArrow schema to an Iceberg schema."""
    type_map = {
        pa.int64(): LongType(),
        pa.int32(): IntegerType(),
        pa.string(): StringType(),
        pa.utf8(): StringType(),
        pa.large_string(): StringType(),
        pa.large_utf8(): StringType(),
    }
    fields = []
    for i, field in enumerate(arrow_schema):
        iceberg_type = type_map.get(field.type, StringType())
        fields.append(
            NestedField(
                field_id=i + 1,
                name=field.name,
                field_type=iceberg_type,
                required=False,
            )
        )
    return Schema(*fields)


def main():
    print("=" * 50)
    print("Iceberg CSV Ingestion - Schema Evolution Test")
    print("=" * 50)

    s3_config = get_s3_config()
    if s3_config:
        print(f"Mode: S3 (bucket={s3_config['bucket']})")
        frames = read_csvs_from_s3(s3_config)
    else:
        print("Mode: Local filesystem")
        frames = read_csvs_from_local()

    if not frames:
        return

    print(f"\nFound {len(frames)} CSV file(s)")

    # Union all frames with diagonal concat (fills missing columns with null)
    print("\nCombining all files with schema union...")
    combined = pl.concat(frames, how="diagonal")
    print(f"  Unified columns: {combined.columns}")
    print(f"  Total rows: {len(combined)}")

    # Convert to Arrow and write to Iceberg
    arrow_table = combined.to_arrow()

    catalog = create_catalog(s3_config)
    table_id = f"{NAMESPACE}.{TABLE_NAME}"
    iceberg_schema = iceberg_schema_from_arrow(arrow_table.schema)

    table = catalog.create_table(table_id, schema=iceberg_schema)
    table.append(arrow_table)
    print(f"\n  Created Iceberg table and inserted {len(combined)} rows")

    # Validation: read back from the Iceberg table and count rows
    print("\n" + "=" * 50)
    print("Validation: Reading back from Iceberg table")
    print("=" * 50)

    table = catalog.load_table(table_id)
    result = table.scan().to_arrow()

    print(f"\nFinal table schema:")
    for field in table.schema().fields:
        print(f"  - {field.name}: {field.field_type}")

    print(f"\nTotal rows written: {len(combined)}")
    print(f"Total rows in table: {len(result)}")

    if len(result) == len(combined):
        print("\nVALIDATION PASSED: Row counts match!")
    else:
        print(f"\nVALIDATION FAILED: Expected {len(combined)}, got {len(result)}")

    warehouse = f"s3://{s3_config['bucket']}/warehouse" if s3_config else str(SCRIPT_DIR / "output" / "warehouse")
    print(f"\nWarehouse location: {warehouse}")


if __name__ == "__main__":
    main()
