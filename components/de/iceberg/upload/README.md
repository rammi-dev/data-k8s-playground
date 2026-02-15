# Iceberg CSV Upload

Ingests CSV files into an Apache Iceberg table using PyIceberg and Polars.
Tests schema evolution by combining CSVs with different column layouts (renamed, added, deleted columns).

Supports two modes: **local filesystem** (default) or **Ceph S3** (via env vars).

## Prerequisites

- Python 3.12+
- [uv](https://docs.astral.sh/uv/) (`curl -LsSf https://astral.sh/uv/install.sh | sh`)
- For S3 mode: running Ceph cluster with S3 object store

## Setup

```bash
cd components/de/iceberg/upload
uv sync
```

## Run (local mode)

```bash
# Option 1: via wrapper script (handles venv + deps + cleanup automatically)
./scripts/ingest.sh

# Option 2: manually (venv must exist)
rm -rf output                        # clean previous run
.venv/bin/python ingest.py
```

## Run (S3 mode)

First, create the S3 infrastructure (bucket + upload CSVs):

```bash
./components/de/iceberg/infra/scripts/build.sh
```

Then run ingestion — the wrapper script auto-detects the RGW service and starts a port-forward:

```bash
# Option 1: via wrapper script (recommended — handles everything automatically)
./scripts/ingest.sh

# Option 2: manually (start port-forward yourself)
kubectl -n rook-ceph port-forward svc/rook-ceph-rgw-s3-store 7481:80 &
export S3_ENDPOINT=http://localhost:7481
export S3_BUCKET=iceberg-upload
export AWS_ACCESS_KEY_ID=minio
export AWS_SECRET_ACCESS_KEY=minio123

rm -rf output
.venv/bin/python ingest.py
```

To tear down the S3 infrastructure:

```bash
./components/de/iceberg/infra/scripts/destroy.sh
```

## Browse bucket in Ceph Dashboard

1. Start the Ceph dashboard and RGW port-forwards:
   ```bash
   ./components/ceph/scripts/dashboard.sh
   ```
2. Open http://localhost:7000 in your browser
3. Login with user `admin` and password from the script output
4. Navigate to **Object Gateway > Buckets** to see the `iceberg-upload` bucket
5. Click the bucket to view objects under `source/` and `warehouse/` prefixes

You can also browse via AWS CLI. The RGW service runs inside K8s, so you need a port-forward first:

```bash
# Start port-forward to RGW (if not already running via dashboard.sh)
kubectl -n rook-ceph port-forward svc/rook-ceph-rgw-s3-store 7480:80 &

export AWS_ENDPOINT_URL=http://localhost:7480
export AWS_ACCESS_KEY_ID=minio
export AWS_SECRET_ACCESS_KEY=minio123
aws s3 ls s3://iceberg-upload/
aws s3 ls s3://iceberg-upload/source/csv/
aws s3 ls s3://iceberg-upload/warehouse/ --recursive
```

> **Note:** `dashboard.sh` already port-forwards RGW on port 7480. If it's running, skip the `kubectl port-forward` step.

## Clean up

```bash
rm -rf output    # remove local Iceberg catalog (SQLite)
rm -rf .venv     # remove virtual environment
```

Both `output/` and `.venv/` are gitignored.

## Source files

Source data lives in `source/` with two formats:

```
source/
├── csv/                              # Raw CSV files (used by ingestion)
│   ├── employees_added.csv
│   ├── employees_deleted.csv
│   └── employees_renamed.csv
└── zip/                              # Zipped CSVs in numbered batches
    ├── 01/employees/                 # Batch 1: base schema evolution set
    │   ├── employees_added.zip
    │   ├── employees_deleted.zip
    │   └── employees_renamed.zip
    ├── 02/employees/                 # Batch 2: new columns (salary, office)
    │   ├── employees_salary.zip
    │   └── employees_location.zip
    └── 03/employees/                 # Batch 3: contractors + promotions
        ├── contractors.zip
        └── employees_promoted.zip
```

### CSV files (source/csv/)

| File | Schema change | Columns |
|------|--------------|---------|
| `employees_added.csv` | Column added | id, name, age, department, **email** |
| `employees_deleted.csv` | Column removed | id, name, department |
| `employees_renamed.csv` | Column renamed | id, **full_name**, age, department |

### ZIP batches (source/zip/)

| Batch | File | Schema | Columns |
|-------|------|--------|---------|
| 01 | `employees_added.zip` | Column added | id, name, age, department, email |
| 01 | `employees_deleted.zip` | Column removed | id, name, department |
| 01 | `employees_renamed.zip` | Column renamed | id, full_name, age, department |
| 02 | `employees_salary.zip` | New column | id, name, age, department, **salary** |
| 02 | `employees_location.zip` | New column | id, name, department, **office** |
| 03 | `contractors.zip` | Different entity | id, full_name, department, **start_date**, **hourly_rate** |
| 03 | `employees_promoted.zip` | New column | id, name, age, department, **title** |

The ingestion script reads CSVs from `source/csv/`, unions their schemas via `pl.concat(how="diagonal")`, and writes a single Iceberg table. Missing columns are filled with null.

Both CSV and ZIP files are uploaded to S3 under `source/csv/` and `source/zip/` prefixes.

## Explore with Jupyter

After running the ingestion, launch JupyterLab to interactively analyze the Iceberg table:

```bash
.venv/bin/jupyter lab explore.ipynb
```

The notebook includes: schema inspection, snapshot history, full table scan, null analysis (schema evolution gaps), filter examples, group-by queries, and data file details.

## Scripts

All scripts assume port-forward is running and env vars are set:

```bash
source scripts/port-forward.sh        # start port-forward + export env vars
source .venv/bin/activate             # activate venv
```

### ZIP to Parquet

Convert zipped CSVs from S3 to Parquet files on S3:

```bash
./zip_to_parquet.py 01 employees      # convert batch 01
./zip_to_parquet.py all employees     # convert all batches
```

### Spark Ingest

Read Parquet from S3, merge schemas, and create an Iceberg table:

```bash
./spark_ingest.py                     # all batches, S3 warehouse
./spark_ingest.py --batch 01          # only batch 01
./spark_ingest.py --entity employees  # entity subfolder (default: employees)
./spark_ingest.py --threads 2         # limit Spark threads
```

### Spark Query

Execute SQL files against Iceberg tables:

```bash
./spark_query.py                      # runs sql/select-all.sql
./spark_query.py sql/my-query.sql     # run custom SQL file
./spark_query.py --warehouse local    # query local warehouse
```

SQL files live in `sql/` and can contain multiple statements separated by `;`.
Supports any Spark SQL: SELECT, INSERT, MERGE, DELETE, ALTER TABLE, etc.
