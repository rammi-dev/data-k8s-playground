# Istio 1.28 to 1.29 Upgrade Notes

## Breaking Changes

### HTTP Compression of Metrics Now Default

Envoy sidecar metrics endpoints now serve compressed responses (brotli/gzip/zstd) by default. The `sidecar.istio.io/statsCompression` annotation is removed.

**Impact**: Monitoring tools scraping raw Prometheus metrics must accept compressed responses.

**Workaround** (per-pod):
```yaml
annotations:
  proxy.istio.io/config: |
    proxyStatsMatcher:
      statsCompression: false
```

### Base Chart Restructuring

Duplicated configurations removed from `base` chart (now in `istiod`). ClusterRole/ClusterRoleBinding names changed to include revision suffixes.

**Impact**: Helm value overrides targeting `base` chart resources may need to move to `istiod`.

### Circuit Breaker Metrics Disabled by Default

`remaining_cx`, `remaining_pending`, `remaining_rq` metrics no longer emitted.

**Workaround**: Set `DISABLE_TRACK_REMAINING_CB_METRICS=false` in istiod env.

### Debug Endpoint Authorization

Port 15014 debug endpoints now restricted by namespace. Non-system namespaces can only access `config_dump`, `ndsz`, `edsz`.

**Impact**: Kiali and custom monitoring may lose access.

**Workaround**: Set `ENABLE_DEBUG_ENDPOINT_AUTH=false` in istiod env.

## New Features

| Feature | Status | Details |
|---------|--------|---------|
| Gateway API Inference Extension | Beta | InferenceModel + InferencePool for AI/LLM serving |
| Ambient multicluster | Beta | Cross-cluster mesh with improved telemetry |
| DNS capture for ambient | Default on | `cni.ambient.dnsCapture=true` |
| iptables reconciliation | Default on | Auto-upgrades rules on cni restart |
| CRL support in ztunnel | New | Validate external CA certificates |
| Dry-run AuthorizationPolicy | Alpha | Test policies without enforcing (ztunnel only) |
| Wildcard hosts in ServiceEntry | Alpha | DYNAMIC_DNS for TLS routing |
| LEAST_REQUEST for gRPC | New | Proxyless gRPC load balancing |

## Kubernetes Compatibility

Istio 1.29 supports Kubernetes **1.31 through 1.35**.
