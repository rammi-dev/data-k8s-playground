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
export S3_BUCKET=$(kubectl -n rook-ceph get cm iceberg-upload -o jsonpath='{.data.BUCKET_NAME}')
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
4. Navigate to **Object Gateway > Buckets** to see the `iceberg-upload-*` bucket
5. Click the bucket to view objects under `csv/` and `warehouse/` prefixes

You can also browse via AWS CLI. The RGW service runs inside K8s, so you need a port-forward first:

```bash
# Start port-forward to RGW (if not already running via dashboard.sh)
kubectl -n rook-ceph port-forward svc/rook-ceph-rgw-s3-store 7480:80 &

export AWS_ENDPOINT_URL=http://localhost:7480
export AWS_ACCESS_KEY_ID=minio
export AWS_SECRET_ACCESS_KEY=minio123
BUCKET=$(kubectl -n rook-ceph get cm iceberg-upload -o jsonpath='{.data.BUCKET_NAME}')

aws s3 ls s3://$BUCKET/
aws s3 ls s3://$BUCKET/csv/
aws s3 ls s3://$BUCKET/warehouse/ --recursive
```

> **Note:** `dashboard.sh` already port-forwards RGW on port 7480. If it's running, skip the `kubectl port-forward` step.

## Clean up

```bash
rm -rf output    # remove local Iceberg catalog (SQLite)
rm -rf .venv     # remove virtual environment
```

Both `output/` and `.venv/` are gitignored.

## CSV test files

| File | Schema change | Columns |
|------|--------------|---------|
| `employees_added.csv` | Column added | id, name, age, department, **email** |
| `employees_deleted.csv` | Column removed | id, name, department |
| `employees_renamed.csv` | Column renamed | id, **full_name**, age, department |

The script reads all CSVs, unions their schemas via `pl.concat(how="diagonal")`, and writes a single Iceberg table. Missing columns are filled with null.

## Explore with Jupyter

After running the ingestion, launch JupyterLab to interactively analyze the Iceberg table:

```bash
.venv/bin/jupyter lab explore.ipynb
```

The notebook includes: schema inspection, snapshot history, full table scan, null analysis (schema evolution gaps), filter examples, group-by queries, and data file details.
