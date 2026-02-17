# Istio Service Mesh

Service mesh for the event-driven playground. Replaces Envoy Gateway with full mesh capabilities (mTLS, AuthorizationPolicy, distributed tracing, L7 metrics). Phase 3 component.

| Property | Value |
|----------|-------|
| Istio | 1.29.0 |
| Charts | base + istiod (umbrella) |
| Mode | Sidecar (ambient not yet Knative-compatible) |
| Namespace | istio-system |

## Prerequisites

- Kubernetes cluster accessible via kubectl
- Knative deployed (build.sh swaps the Gateway API controller)
- `components.istio.enabled: true` in config.yaml

## Usage

```bash
# Deploy (swaps Gateway API controller from Envoy Gateway to Istio)
./scripts/build.sh

# Then remove Envoy Gateway
../envoy-gateway/scripts/destroy.sh

# Test
./scripts/test/test-mesh.sh

# Destroy
./scripts/destroy.sh

# Render templates for inspection
./scripts/regenerate-rendered.sh [--clean]
```

## Docs

| Document | Content |
|----------|---------|
| [Architecture](docs/architecture.md) | Control plane, data plane, sidecar injection, mTLS, Gateway API |
| [AI Serving](docs/ai-serving.md) | Gateway API Inference Extension, InferencePool, InferenceModel, LLM routing |
| [Upgrade Notes](docs/upgrade-notes.md) | 1.28 to 1.29 breaking changes and migration |

## File Structure

```
istio/
├── README.md
├── docs/
│   ├── architecture.md
│   ├── ai-serving.md
│   └── upgrade-notes.md
├── helm/
│   ├── Chart.yaml                  # Wrapper chart (base + istiod 1.29.0)
│   ├── values.yaml                 # Gateway API enabled, resource limits
│   └── values-overrides.yaml       # Environment-specific overrides
├── manifests/
│   ├── peer-authentication.yaml    # mTLS STRICT mesh-wide
│   └── authz-knative.yaml          # Allow Knative system namespaces
├── deployment/
│   └── rendered/                   # Output of regenerate-rendered.sh
└── scripts/
    ├── build.sh                    # Install + swap gateway + apply policies
    ├── destroy.sh                  # Full teardown (CRDs, namespace, sidecars)
    ├── regenerate-rendered.sh
    └── test/
        └── test-mesh.sh
```
