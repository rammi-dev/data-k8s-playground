# Envoy Gateway

Gateway API controller for the event-driven playground (Phase 1-2).

## Chart Versions

| Component | Version |
|-----------|---------|
| Envoy Gateway | v1.7.0 |
| Gateway API | v1.4.1 |
| Envoy Proxy | v1.37.0 |

## API Reference

- [Envoy Gateway API Extensions](https://gateway.envoyproxy.io/docs/api/extension_types/) — BackendTrafficPolicy, ClientTrafficPolicy, SecurityPolicy, EnvoyProxy CRDs
- [Gateway API Spec](https://gateway-api.sigs.k8s.io/reference/spec/) — GatewayClass, Gateway, HTTPRoute (upstream K8s standard)

## Components

| Service | Role |
|---------|------|
| envoy-gateway (controller) | Reconciles Gateway API CRDs, provisions Envoy proxies |
| envoy proxy (per Gateway) | Data plane — routes traffic based on HTTPRoute rules |
| GatewayClass `eg` | Auto-created — identifies this controller |

## Prerequisites

- Kubernetes cluster accessible via kubectl
- `components.envoy_gateway.enabled: true` in config.yaml

## Configuration

Edit `helm/values.yaml` for controller settings. Gateway resource in `helm/templates/custom/gateway.yaml`.

## Usage

```bash
# Deploy
./scripts/build.sh

# Destroy
./scripts/destroy.sh
```

## Gateway API Resources

After deployment, you interact with standard Gateway API resources:

```bash
kubectl get gatewayclass       # Should show 'eg'
kubectl get gateway -A         # Should show 'knative-gateway'
kubectl get httproute -A       # Created automatically by Knative
```

## Phase 3 Migration

When switching to Istio, change `gatewayClassName` in `helm/templates/custom/gateway.yaml` from `eg` to `istio`, then disable this component and enable Istio in config.yaml.

## File Structure

```
envoy-gateway/
├── README.md
├── deployment/              # Rendered output (.gitignore)
├── docs/
├── helm/
│   ├── Chart.yaml           # Documents OCI chart dependency
│   ├── values.yaml          # Controller configuration
│   ├── values-overrides.yaml
│   └── templates/custom/
│       └── gateway.yaml     # Gateway resource for Knative
└── scripts/
    ├── build.sh             # Deploy controller + Gateway
    ├── destroy.sh           # Full teardown
    ├── regenerate-rendered.sh
    └── test/
        └── test-gateway.sh  # Test: GatewayClass, Gateway, CRDs
```
