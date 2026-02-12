# Airflow Component

Apache Airflow workflow orchestration platform deployed via the official Helm chart.

## Chart Versions

See [helm/Chart.yaml](helm/Chart.yaml) for pinned versions.

| Chart | Version | App Version | Description |
|-------|---------|-------------|-------------|
| **airflow** | 1.18.0 | 3.1.7 | Official Apache Airflow Helm chart |

## Components

| Component | Purpose |
|-----------|---------|
| **Webserver** | Airflow UI (port 8080) |
| **Scheduler** | DAG scheduling and task execution |
| **Triggerer** | Async trigger handling (deferrable operators) |
| **PostgreSQL** | Metadata database (bundled subchart) |

Executor: **KubernetesExecutor** — no Redis or Celery workers needed. Each task runs as a separate K8s pod.

## Configuration

Enable airflow in `config.yaml`:

```yaml
components:
  airflow:
    enabled: true
    namespace: "airflow"
    chart_repo: "https://airflow.apache.org"
    chart_name: "airflow"
    chart_version: "1.18.0"
```

Customize Helm values in `helm/values.yaml`.

## Usage

### Deploy Airflow

```bash
./components/airflow/scripts/build.sh
```

### Access Webserver

```bash
./components/airflow/scripts/access-webserver.sh
```

This starts port-forwarding. Access at http://localhost:8080

### Check Status

```bash
kubectl get pods -n airflow
kubectl get svc -n airflow
```

### Remove Airflow

```bash
./components/airflow/scripts/destroy.sh
```

## Helm Dependency

The chart dependency (tgz) is downloaded via `helm dependency update` and stored in `helm/charts/`. This directory is gitignored — run `helm dependency update helm/` to regenerate after cloning.

## Troubleshooting

### Pods not starting

```bash
kubectl get pods -n airflow
kubectl get events -n airflow --sort-by='.lastTimestamp'
kubectl logs -n airflow <pod-name>
```

### Database migration issues

```bash
# Check the migration job
kubectl get jobs -n airflow
kubectl logs -n airflow -l job-name=airflow-run-airflow-migrations
```
