#!/usr/bin/env python3
"""Expire old Iceberg snapshots, keeping only the latest.

Works around Spark 4.1 / Iceberg 1.10.0 CALL procedure incompatibility
by using the Iceberg Java API directly through Spark's JVM gateway.

Quick start:
  source scripts/port-forward.sh
  source .venv/bin/activate
  ./spark_expire.py                    # keep 1 snapshot (default)
  ./spark_expire.py --retain 3         # keep last 3 snapshots

Uses same S3 env vars as spark_ingest.py / spark_query.py.
"""

import argparse
import os
import time

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


def create_spark(warehouse: str, threads: str = "1") -> SparkSession:
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

    builder = (
        SparkSession.builder
        .appName("iceberg-expire-snapshots")
        .master(f"local[{threads}]")
        .config("spark.jars.packages", f"{ICEBERG_SPARK_JAR},{HADOOP_AWS_JAR}")
        .config("spark.sql.catalog.iceberg_test", "org.apache.iceberg.spark.SparkCatalog")
        .config("spark.sql.catalog.iceberg_test.type", "hadoop")
        .config("spark.sql.catalog.iceberg_test.warehouse", warehouse_path)
        .config("spark.hadoop.fs.s3a.endpoint", endpoint)
        .config("spark.hadoop.fs.s3a.access.key", access_key)
        .config("spark.hadoop.fs.s3a.secret.key", secret_key)
        .config("spark.hadoop.fs.s3a.path.style.access", "true")
        .config("spark.hadoop.fs.s3a.impl", "org.apache.hadoop.fs.s3a.S3AFileSystem")
        .config("spark.hadoop.fs.s3a.connection.ssl.enabled", "false")
        .config("spark.sql.extensions", "org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions")
        .config("spark.sql.defaultCatalog", "iceberg_test")
    )

    return builder.getOrCreate()


def main():
    parser = argparse.ArgumentParser(description="Expire old Iceberg snapshots")
    parser.add_argument("--retain", type=int, default=1, help="Number of snapshots to keep (default: 1)")
    parser.add_argument("--warehouse", default="s3", choices=["s3", "local"], help="Warehouse location (default: s3)")
    args = parser.parse_args()

    spark = create_spark(args.warehouse)

    # Show snapshots before
    print("Snapshots BEFORE:")
    spark.sql(f"SELECT snapshot_id, committed_at, operation FROM {TABLE_NAME}.snapshots").show(truncate=False)

    # Load Iceberg table via HadoopTables (bypasses broken Spark procedure)
    jvm = spark._jvm
    hadoop_conf = spark._jsc.hadoopConfiguration()
    tables = jvm.org.apache.iceberg.hadoop.HadoopTables(hadoop_conf)

    endpoint = env("S3_ENDPOINT")
    bucket = env("S3_BUCKET")
    if args.warehouse == "s3":
        table_path = f"s3a://{bucket}/warehouse/employees"
    else:
        table_path = os.path.join(
            os.path.dirname(os.path.abspath(__file__)), "output", "spark-warehouse", "employees"
        )

    iceberg_table = tables.load(table_path)

    # Override the default 5-day safety threshold so recently-created
    # snapshots can actually be expired and their data files deleted.
    now_ms = int(time.time() * 1000)
    iceberg_table.expireSnapshots() \
        .retainLast(args.retain) \
        .expireOlderThan(now_ms) \
        .commit()

    print(f"\nExpired snapshots (retained last {args.retain})")

    # Remove orphan data files not referenced by any current snapshot.
    # Uses Spark SQL metadata tables instead of Java iterators via py4j.
    print("\nCleaning orphan data files...")
    referenced_rows = spark.sql(f"SELECT file_path FROM {TABLE_NAME}.files").collect()
    referenced = {row.file_path for row in referenced_rows}
    print(f"  Referenced files: {len(referenced)}")

    # List all files under the table's data/ directory via Hadoop FS
    data_path = table_path + "/data"
    hadoop_path = jvm.org.apache.hadoop.fs.Path(data_path)
    fs = hadoop_path.getFileSystem(hadoop_conf)

    orphans = []
    if fs.exists(hadoop_path):
        file_iter = fs.listFiles(hadoop_path, True)
        while file_iter.hasNext():
            path_str = str(file_iter.next().getPath())
            if path_str not in referenced:
                orphans.append(path_str)

    if orphans:
        print(f"  Deleting {len(orphans)} orphan files...")
        for orphan in orphans:
            fs.delete(jvm.org.apache.hadoop.fs.Path(orphan), False)
        print(f"  Deleted {len(orphans)} orphan files")
    else:
        print("  No orphan files found")

    # Show snapshots after
    print("\nSnapshots AFTER:")
    spark.sql(f"SELECT snapshot_id, committed_at, operation FROM {TABLE_NAME}.snapshots").show(truncate=False)

    spark.stop()
    print("Done!")


if __name__ == "__main__":
    main()
