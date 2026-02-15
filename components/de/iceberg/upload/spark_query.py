#!/usr/bin/env python3
"""Execute SQL queries against Iceberg tables using Spark.

Quick start:
  source scripts/port-forward.sh        # start port-forward + export env vars
  source .venv/bin/activate             # activate venv (uv sync first if needed)
  ./spark_query.py                      # run default select-all.sql
  ./spark_query.py sql/my-query.sql     # run custom SQL file

Usage:
  ./spark_query.py                      # runs sql/select-all.sql
  ./spark_query.py sql/snapshots.sql    # run specific SQL file
  ./spark_query.py --warehouse local    # query local warehouse
  ./spark_query.py --threads 2          # limit to 2 Spark threads

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

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DEFAULT_SQL = os.path.join(SCRIPT_DIR, "sql", "select-all.sql")


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
        warehouse_path = os.path.join(SCRIPT_DIR, "output", "spark-warehouse")

    builder = (
        SparkSession.builder
        .appName("iceberg-spark-query")
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
    parser = argparse.ArgumentParser(description="Execute SQL against Iceberg tables via Spark")
    parser.add_argument("sql_file", nargs="?", default=DEFAULT_SQL, help=f"SQL file to execute (default: sql/select-all.sql)")
    parser.add_argument("--warehouse", default="s3", choices=["s3", "local"], help="Warehouse location (default: s3)")
    parser.add_argument("--threads", default="*", help="Number of Spark threads (default: *)")
    args = parser.parse_args()

    if not os.path.isfile(args.sql_file):
        print(f"SQL file not found: {args.sql_file}")
        sys.exit(1)

    with open(args.sql_file) as f:
        sql_text = f.read().strip()

    # Split on semicolons, filter empty
    statements = [s.strip() for s in sql_text.split(";") if s.strip()]

    used_defaults = [k for k in DEFAULTS if not os.environ.get(k)]
    if used_defaults:
        print(f"Using defaults for: {', '.join(used_defaults)}")

    print(f"SQL file:  {args.sql_file}")
    print(f"Warehouse: {args.warehouse}")
    print(f"Statements: {len(statements)}")
    print()

    spark = create_spark(args.warehouse, args.threads)

    for i, stmt in enumerate(statements, 1):
        print(f"--- Statement {i} ---")
        print(stmt)
        print()
        result = spark.sql(stmt)
        if result.columns:
            result.show(truncate=False)
        else:
            print("OK\n")

    spark.stop()
    print("Done!")


if __name__ == "__main__":
    main()
