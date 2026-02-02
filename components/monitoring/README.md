# Monitoring Component

Loki Stack provides comprehensive monitoring for Kubernetes using Grafana, Prometheus, Loki, and Promtail.

## Chart Versions

See [helm/Chart.yaml](helm/Chart.yaml) for pinned versions.

| Chart | Version | Description |
|-------|---------|-------------|
| **loki-stack** | 2.10.3 | Parent chart (deprecated but functional) |
| loki | ^2.15.2 | Log aggregation system |
| promtail | ^6.7.4 | Log collection agent |
| grafana | ~6.43.0 | Visualization & dashboards |
| prometheus | ~19.7.2 | Metrics collection & alerting |

## Components

| Component | Purpose |
|-----------|---------|
| **Grafana** | Visualization and dashboards |
| **Prometheus** | Metrics collection and alerting |
| **Loki** | Log aggregation |
| **Promtail** | Log collection agent |

## Configuration

Enable monitoring in `config.yaml`:

```yaml
components:
  monitoring:
    enabled: true
    namespace: "monitoring"
    grafana_storage: "5Gi"
    prometheus_storage: "8Gi"
```

Customize Helm values in `helm/values.yaml`.

## Usage

### Deploy Monitoring

```bash
cd /vagrant
./components/monitoring/scripts/build.sh
```

### Access Grafana

```bash
./components/monitoring/scripts/access-grafana.sh
```

This displays credentials and starts port-forwarding. Access at http://localhost:3000

**From Windows host:** See [Networking Guide](../../docs/NETWORKING.md) for accessing services from outside the VM.

### Check Status

```bash
kubectl get pods -n monitoring
kubectl get svc -n monitoring
```

### Remove Monitoring

```bash
./components/monitoring/scripts/destroy.sh
```

## Pre-configured Dashboards

The following Grafana dashboards are automatically provisioned:

| Dashboard | ID | Description |
|-----------|----|-------------|
| Kubernetes Cluster | 6417 | Overall cluster health |
| Kubernetes Nodes | 15762 | Node-level metrics |
| Node Exporter | 1860 | Detailed node metrics |
| Kubernetes Deployments | 15760 | Deployment status |
| Kubernetes StatefulSets | 15761 | StatefulSet status |
| Kubernetes Pods | 15763 | Pod-level metrics |
| Persistent Volumes | 13646 | Storage metrics |
| Kubernetes Namespaces | 15758 | Namespace overview |

## Data Sources

Grafana is pre-configured with:

- **Prometheus** (default) - For metrics queries
- **Loki** - For log queries

## Storage

Both Grafana and Prometheus use persistent storage via the `csi-hostpath-sc` storage class:

- Grafana: 5Gi
- Prometheus: 8Gi

## Troubleshooting

### Pods not starting

```bash
# Check pod status
kubectl get pods -n monitoring

# Check events
kubectl get events -n monitoring --sort-by='.lastTimestamp'

# Check specific pod logs
kubectl logs -n monitoring <pod-name>
```

### Grafana password reset

```bash
# Get current password
kubectl get secret -n monitoring loki-grafana -o jsonpath="{.data.admin-password}" | base64 -d
```

### Metrics not showing

```bash
# Verify Prometheus is scraping targets
kubectl port-forward -n monitoring svc/loki-prometheus-server 9090:80
# Open http://localhost:9090/targets
```
