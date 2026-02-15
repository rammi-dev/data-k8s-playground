#!/usr/bin/env python3
"""Convert ZIP files (containing CSVs) from S3 to Parquet.

Reads zips from source/zip/{batch}/{entity}/, converts each CSV inside
to Parquet, and writes to source/parquet/{batch}/{entity}/ in the same bucket.

Usage:
  ./zip_to_parquet.py <batch> <entity>
  ./zip_to_parquet.py 01 employees
  ./zip_to_parquet.py all employees    # process all batches

Uses S3_ENDPOINT, S3_BUCKET, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY env vars.
If not provided, defaults to localhost:7481 with minio/minio123 credentials.
"""

import io
import sys
import os
import zipfile

import polars as pl
import s3fs


DEFAULTS = {
    "S3_ENDPOINT": "http://localhost:7481",
    "S3_BUCKET": "iceberg-upload",
    "AWS_ACCESS_KEY_ID": "minio",
    "AWS_SECRET_ACCESS_KEY": "minio123",
}


def env(var: str) -> str:
    return os.environ.get(var) or DEFAULTS[var]


def get_s3_fs() -> s3fs.S3FileSystem:
    return s3fs.S3FileSystem(
        key=env("AWS_ACCESS_KEY_ID"),
        secret=env("AWS_SECRET_ACCESS_KEY"),
        endpoint_url=env("S3_ENDPOINT"),
    )


def convert_batch(fs: s3fs.S3FileSystem, bucket: str, batch: str, entity: str):
    """Convert all zips in one batch/entity folder to parquet."""
    zip_prefix = f"{bucket}/source/zip/{batch}/{entity}"
    parquet_prefix = f"{bucket}/source/parquet/{batch}/{entity}"

    zip_files = sorted(fs.glob(f"{zip_prefix}/*.zip"))
    if not zip_files:
        print(f"  No zip files found in s3://{zip_prefix}/")
        return 0

    count = 0
    for zip_path in zip_files:
        zip_name = zip_path.split("/")[-1]
        base_name = zip_name.replace(".zip", "")

        # Download and extract CSV from zip
        with fs.open(zip_path, "rb") as f:
            with zipfile.ZipFile(io.BytesIO(f.read())) as zf:
                csv_names = [n for n in zf.namelist() if n.endswith(".csv")]
                if not csv_names:
                    print(f"  SKIP {zip_name}: no CSV inside")
                    continue
                csv_data = zf.read(csv_names[0])

        # Convert to parquet via polars
        df = pl.read_csv(io.BytesIO(csv_data))
        parquet_buf = io.BytesIO()
        df.write_parquet(parquet_buf)
        parquet_buf.seek(0)

        # Upload parquet
        parquet_path = f"{parquet_prefix}/{base_name}.parquet"
        with fs.open(parquet_path, "wb") as f:
            f.write(parquet_buf.read())

        print(f"  {zip_name} -> {base_name}.parquet ({len(df)} rows, {df.columns})")
        count += 1

    return count


def main():
    if len(sys.argv) != 3:
        print("Usage: python zip_to_parquet.py <batch|all> <entity>")
        print("  e.g.: python zip_to_parquet.py 01 employees")
        print("        python zip_to_parquet.py all employees")
        sys.exit(1)

    batch_arg = sys.argv[1]
    entity = sys.argv[2]
    bucket = env("S3_BUCKET")

    used_defaults = [k for k in DEFAULTS if not os.environ.get(k)]
    if used_defaults:
        print(f"Using defaults for: {', '.join(used_defaults)}")

    fs = get_s3_fs()

    # Discover batches
    if batch_arg == "all":
        zip_root = f"{bucket}/source/zip"
        batches = sorted([p.split("/")[-1] for p in fs.ls(zip_root) if fs.isdir(p)])
    else:
        batches = [batch_arg]

    total = 0
    for batch in batches:
        print(f"\nBatch {batch}/{entity}:")
        converted = convert_batch(fs, bucket, batch, entity)
        total += converted

    print(f"\nDone: {total} file(s) converted to parquet")


if __name__ == "__main__":
    main()
