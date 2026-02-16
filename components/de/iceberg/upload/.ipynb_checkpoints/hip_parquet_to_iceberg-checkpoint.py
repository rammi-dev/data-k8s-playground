#!/usr/bin/env python3
"""Read HIP parquet files from S3 and write to Iceberg tables using Spark.

Reads parquet files from s3a://dlh-lab/parquet/<TABLE_NAME>/ and creates
an Iceberg table under the configured warehouse path.

Usage:
  ./hip_parquet_to_iceberg.py RBES_ZASGENMAG              # ingest one table
  ./hip_parquet_to_iceberg.py RBES_ZASGENMAG --list        # list parquet files only
  ./hip_parquet_to_iceberg.py RBES_ZASGENMAG --warehouse local  # local warehouse

Uses S3_ENDPOINT, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY env vars.
If not provided, defaults to https://localhost:9000 with minio/minio123 credentials.

Optional env vars:
  S3_SOURCE_BUCKET  (default: dlh-lab)
  S3_TARGET_BUCKET  (default: dlh-lab)
  ICEBERG_WAREHOUSE (default: s3a://dlh-lab/iceberg-rammi)
"""

import argparse
import os
import sys

from pyspark.sql import SparkSession
from pyspark.sql import functions as F

DEFAULTS = {
    "S3_ENDPOINT": "https://minio-dev.service.dc1.consul:9000",
    "AWS_ACCESS_KEY_ID": "minio",
    "AWS_SECRET_ACCESS_KEY": "minio123",
    "S3_SOURCE_BUCKET": "dlh-lab",
    "S3_TARGET_BUCKET": "dlh-lab",
    "ICEBERG_WAREHOUSE": "s3a://dlh-lab/iceberg-rammi",
}

ICEBERG_SPARK_JAR = "org.apache.iceberg:iceberg-spark-runtime-4.0_2.13:1.10.0"
HADOOP_AWS_JAR = "org.apache.hadoop:hadoop-aws:3.4.1"

CATALOG_NAME = "hip_catalog"
NAMESPACE = "hip"


def env(var: str, default: str = "") -> str:
    return os.environ.get(var) or DEFAULTS.get(var, default)


def create_spark(warehouse_path: str, threads: str = "*") -> SparkSession:
    endpoint = env("S3_ENDPOINT")
    access_key = env("AWS_ACCESS_KEY_ID")
    secret_key = env("AWS_SECRET_ACCESS_KEY")
    ssl_enabled = endpoint.startswith("https://")

    builder = (
        SparkSession.builder
        .appName("hip-parquet-to-iceberg")
        .master(f"local[{threads}]")
        .config("spark.jars.packages", f"{ICEBERG_SPARK_JAR},{HADOOP_AWS_JAR}")
        # Iceberg catalog (hadoop type = file-based, no external metastore needed)
        .config(f"spark.sql.catalog.{CATALOG_NAME}", "org.apache.iceberg.spark.SparkCatalog")
        .config(f"spark.sql.catalog.{CATALOG_NAME}.type", "hadoop")
        .config(f"spark.sql.catalog.{CATALOG_NAME}.warehouse", warehouse_path)
        # S3A / Hadoop config
        .config("spark.hadoop.fs.s3a.endpoint", endpoint)
        .config("spark.hadoop.fs.s3a.access.key", access_key)
        .config("spark.hadoop.fs.s3a.secret.key", secret_key)
        .config("spark.hadoop.fs.s3a.path.style.access", "true")
        .config("spark.hadoop.fs.s3a.impl", "org.apache.hadoop.fs.s3a.S3AFileSystem")
        .config("spark.hadoop.fs.s3a.connection.ssl.enabled", str(ssl_enabled).lower())
        .config("spark.hadoop.fs.s3a.endpoint.region", env("AWS_DEFAULT_REGION", "us-east-1"))
        # Iceberg extensions
        .config("spark.sql.extensions", "org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions")
        .config("spark.sql.defaultCatalog", CATALOG_NAME)
    )

    return builder.getOrCreate()


def main():
    parser = argparse.ArgumentParser(description="Ingest HIP parquet from S3 into Iceberg via Spark")
    parser.add_argument("table", help="Table name (e.g. RBES_ZASGENMAG)")
    parser.add_argument("--warehouse", default="s3", choices=["s3", "local"],
                        help="Warehouse location (default: s3)")
    parser.add_argument("--threads", default="*",
                        help="Spark threads: 1, 2, or * for all (default: *)")
    parser.add_argument("--list", action="store_true",
                        help="List parquet files only, don't ingest")
    args = parser.parse_args()

    source_bucket = env("S3_SOURCE_BUCKET")
    table_name = args.table

    if args.warehouse == "s3":
        warehouse_path = env("ICEBERG_WAREHOUSE")
    else:
        warehouse_path = os.path.join(
            os.path.dirname(os.path.abspath(__file__)), "output", "hip-warehouse"
        )
        os.makedirs(warehouse_path, exist_ok=True)

    used_defaults = [k for k in DEFAULTS if not os.environ.get(k)]
    if used_defaults:
        print(f"Using defaults for: {', '.join(used_defaults)}")

    parquet_path = f"s3a://{source_bucket}/parquet/{table_name}"
    iceberg_table = f"{CATALOG_NAME}.{NAMESPACE}.{table_name}"

    print(f"Source:    {parquet_path}")
    print(f"Warehouse: {warehouse_path}")
    print(f"Table:     {iceberg_table}")
    print()

    spark = create_spark(warehouse_path, args.threads)

    # Discover parquet files via glob
    parquet_glob = f"{parquet_path}/*.parquet"
    hadoop_conf = spark._jsc.hadoopConfiguration()
    hadoop_fs = spark._jvm.org.apache.hadoop.fs.FileSystem.get(
        spark._jvm.java.net.URI(f"s3a://{source_bucket}"), hadoop_conf
    )
    matches = hadoop_fs.globStatus(spark._jvm.org.apache.hadoop.fs.Path(parquet_glob))
    parquet_files = [str(m.getPath()) for m in matches] if matches else []
    print(f"Found {len(parquet_files)} parquet file(s)")

    if args.list:
        for pf in sorted(parquet_files):
            print(f"  {pf.split('/')[-1]}")
        spark.stop()
        return

    if not parquet_files:
        print(f"No parquet files found at {parquet_glob}")
        spark.stop()
        sys.exit(1)

    # Read all parquet files with schema merge
    print("Reading parquet files...")
    df = (
        spark.read
        .option("mergeSchema", "true")
        .parquet(*parquet_files)
        .withColumn("_source_file", F.input_file_name())
    )

    row_count = df.count()
    col_count = len(df.columns)
    print(f"  Rows: {row_count}")
    print(f"  Columns: {col_count}")
    df.printSchema()

    # Create namespace if needed (Spark SQL)
    spark.sql(f"CREATE NAMESPACE IF NOT EXISTS {CATALOG_NAME}.{NAMESPACE}")

    # Write to Iceberg table
    print(f"Writing to Iceberg table '{iceberg_table}'...")
    df.writeTo(iceberg_table).using("iceberg").createOrReplace()

    # Validate
    print("\nValidation:")
    result = spark.table(iceberg_table)
    result_count = result.count()
    print(f"  Rows in table: {result_count}")
    result.show(5, truncate=False)

    if result_count == row_count:
        print("\nVALIDATION PASSED")
    else:
        print(f"\nVALIDATION FAILED: expected {row_count}, got {result_count}")

    spark.sql(f"SELECT * FROM {iceberg_table}.snapshots").show(truncate=False)

    spark.stop()
    print("\nDone!")


if __name__ == "__main__":
    main()
