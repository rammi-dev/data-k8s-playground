#!/usr/bin/env python3
"""Read parquet files from S3 and create an Iceberg table using Spark.

Reads all parquet files from source/parquet/*/employees/*.parquet,
unions them with schema merge, and writes to an Iceberg 'employees' table.

Quick start:
  source scripts/port-forward.sh        # start port-forward + export env vars
  source .venv/bin/activate             # activate venv (uv sync first if needed)
  ./spark_ingest.py                     # run with defaults

Usage:
  ./spark_ingest.py                     # all batches, S3 warehouse, all cores
  ./spark_ingest.py --batch 01          # only batch 01
  ./spark_ingest.py --warehouse local   # local warehouse instead of S3
  ./spark_ingest.py --threads 2         # limit to 2 Spark threads

Uses S3_ENDPOINT, S3_BUCKET, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY env vars.
If not provided, defaults to localhost:7481 with minio/minio123 credentials.
"""

import argparse
import os
import sys

from pyspark.sql import SparkSession

DEFAULTS = {
    "S3_ENDPOINT": "http://localhost:7481",
    "S3_BUCKET": "iceberg-upload",
    "AWS_ACCESS_KEY_ID": "minio",
    "AWS_SECRET_ACCESS_KEY": "minio123",
}

ICEBERG_SPARK_JAR = "org.apache.iceberg:iceberg-spark-runtime-4.0_2.13:1.10.0"
HADOOP_AWS_JAR = "org.apache.hadoop:hadoop-aws:3.4.1"

TABLE_NAME = "iceberg_test.employees"


def env(var: str) -> str:
    return os.environ.get(var) or DEFAULTS[var]


def create_spark(warehouse: str, threads: str = "*") -> SparkSession:
    endpoint = env("S3_ENDPOINT")
    access_key = env("AWS_ACCESS_KEY_ID")
    secret_key = env("AWS_SECRET_ACCESS_KEY")
    bucket = env("S3_BUCKET")

    if warehouse == "s3":
        warehouse_path = f"s3a://{bucket}/warehouse"
    else:
        warehouse_path = os.path.join(
            os.path.dirname(os.path.abspath(__file__)), "output", "spark-warehouse"
        )
        os.makedirs(warehouse_path, exist_ok=True)

    builder = (
        SparkSession.builder
        .appName("iceberg-parquet-ingest")
        .master(f"local[{threads}]")
        .config("spark.jars.packages", f"{ICEBERG_SPARK_JAR},{HADOOP_AWS_JAR}")
        # Iceberg catalog
        .config("spark.sql.catalog.iceberg_test", "org.apache.iceberg.spark.SparkCatalog")
        .config("spark.sql.catalog.iceberg_test.type", "hadoop")
        .config("spark.sql.catalog.iceberg_test.warehouse", warehouse_path)
        # S3 / Hadoop config
        .config("spark.hadoop.fs.s3a.endpoint", endpoint)
        .config("spark.hadoop.fs.s3a.access.key", access_key)
        .config("spark.hadoop.fs.s3a.secret.key", secret_key)
        .config("spark.hadoop.fs.s3a.path.style.access", "true")
        .config("spark.hadoop.fs.s3a.impl", "org.apache.hadoop.fs.s3a.S3AFileSystem")
        .config("spark.hadoop.fs.s3a.connection.ssl.enabled", "false")
        # Iceberg extensions
        .config("spark.sql.extensions", "org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions")
        .config("spark.sql.defaultCatalog", "iceberg_test")
    )

    return builder.getOrCreate()


def main():
    parser = argparse.ArgumentParser(description="Ingest parquet from S3 into Iceberg table via Spark")
    parser.add_argument("--batch", default="all", help="Batch number (01, 02, 03) or all (default: all)")
    parser.add_argument("--entity", default="employees", help="Entity subfolder (default: employees)")
    parser.add_argument("--warehouse", default="s3", choices=["s3", "local"], help="Warehouse location (default: s3)")
    parser.add_argument("--threads", default="*", help="Number of Spark threads: 1, 2, 4, or * for all cores (default: *)")
    args = parser.parse_args()

    bucket = env("S3_BUCKET")

    used_defaults = [k for k in DEFAULTS if not os.environ.get(k)]
    if used_defaults:
        print(f"Using defaults for: {', '.join(used_defaults)}")

    spark = create_spark(args.warehouse, args.threads)

    # Resolve parquet paths using Hadoop globStatus (S3A supports globs here)
    base = f"s3a://{bucket}/source/parquet"
    if args.batch == "all":
        glob_pattern = f"{base}/*/{args.entity}"
    else:
        glob_pattern = f"{base}/{args.batch}/{args.entity}"

    hadoop_conf = spark._jsc.hadoopConfiguration()
    fs = spark._jvm.org.apache.hadoop.fs.FileSystem.get(
        spark._jvm.java.net.URI(base), hadoop_conf
    )
    matches = fs.globStatus(spark._jvm.org.apache.hadoop.fs.Path(glob_pattern))
    parquet_paths = [str(m.getPath()) for m in matches] if matches else []

    if not parquet_paths:
        print(f"No directories matching: {glob_pattern}")
        spark.stop()
        sys.exit(1)

    print(f"Source:    {glob_pattern}  ({len(parquet_paths)} dirs)")
    print(f"Warehouse: {args.warehouse}")
    print(f"Threads:   local[{args.threads}]")
    print(f"Table:     {TABLE_NAME}")
    print()

    # Read all parquet files with schema merge
    print("Reading parquet files...")
    df = spark.read.option("mergeSchema", "true").parquet(*parquet_paths)

    row_count = df.count()
    print(f"  Rows: {row_count}")
    print(f"  Schema:")
    df.printSchema()

    # Create or replace Iceberg table and insert data
    print(f"Writing to Iceberg table '{TABLE_NAME}'...")
    df.writeTo(TABLE_NAME).using("iceberg").createOrReplace()

    # Validate
    print("\nValidation:")
    result = spark.table(TABLE_NAME)
    result_count = result.count()
    print(f"  Rows in table: {result_count}")
    result.show(truncate=False)

    if result_count == row_count:
        print("\nVALIDATION PASSED")
    else:
        print(f"\nVALIDATION FAILED: expected {row_count}, got {result_count}")

    # Show table metadata
    spark.sql(f"SELECT * FROM {TABLE_NAME}.snapshots").show(truncate=False)

    spark.stop()
    print("\nDone!")


if __name__ == "__main__":
    main()
