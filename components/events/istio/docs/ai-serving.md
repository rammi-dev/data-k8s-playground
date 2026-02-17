# AI Serving with Istio

## Overview

Istio 1.29 promotes the **Gateway API Inference Extension** to Beta. This turns Istio's Gateway API implementation into an AI-aware inference gateway that understands LLM workloads, GPU utilization, and model routing.

Traditional load balancing (round-robin, least-connections) fails for LLM inference because:
- Requests take **seconds to minutes** (not milliseconds)
- A single request can **consume an entire GPU**
- **KV cache** utilization directly impacts throughput
- **LoRA adapters** must be loaded into GPU memory; routing to a backend with the adapter already loaded is dramatically faster

## Architecture

```mermaid
graph TB
    Client([Client])

    subgraph gateway["Istio Gateway (Envoy)"]
        route["HTTPRoute<br/>/v1/completions"]
        model["InferenceModel<br/>model: gpt-4<br/>criticality: Critical"]
        pool["InferencePool<br/>gpu-pool"]
        ese["Endpoint Selection Extension"]
    end

    subgraph backends["Model Serving Backends"]
        v1["vLLM-1<br/>GPU 0 | LoRA:A<br/>KV cache: 72%"]
        v2["vLLM-2<br/>GPU 1 | LoRA:B<br/>KV cache: 45%"]
        v3["vLLM-3<br/>GPU 2 | LoRA:A<br/>KV cache: 88%"]
    end

    Client --> route
    route --> model
    model -->|"v1: 90% / v2: 10%"| pool
    pool --> ese
    ese -->|"LoRA affinity + KV cache"| v1
    ese -.->|"low cache"| v2
    ese -->|"prefix match"| v3

    style gateway fill:#e8f4fd,stroke:#1a73e8
    style backends fill:#fce8e6,stroke:#d93025
    style ese fill:#e6f4ea,stroke:#137333
```

## Request Flow

```mermaid
sequenceDiagram
    participant C as Client
    participant G as Istio Gateway
    participant IM as InferenceModel
    participant ESE as Endpoint Picker
    participant B as vLLM Backend

    C->>G: POST /v1/completions<br/>model: gpt-4
    G->>IM: Resolve model name
    IM-->>G: targetModels + criticality
    G->>ESE: Pick best endpoint
    Note over ESE: Check KV cache utilization<br/>Check LoRA adapter loaded<br/>Check queue depth<br/>Check GPU memory
    ESE-->>G: backend-2 (best fit)
    G->>B: Forward request
    B-->>G: Stream tokens
    G-->>C: Stream response
```

## CRDs

### InferenceModel

Defined by AI engineers / model owners. Maps a logical model name to serving backends with traffic splitting and priority.

```yaml
apiVersion: inference.networking.x-k8s.io/v1alpha2
kind: InferenceModel
metadata:
  name: my-model
spec:
  modelName: gpt-4
  criticality: Critical        # Critical | Standard | Sheddable
  poolRef:
    name: gpu-pool
  targetModels:
    - name: gpt-4-v1
      weight: 90
    - name: gpt-4-v2
      weight: 10               # canary 10% to new version
```

**Criticality levels** control behavior under load:
- **Critical**: Never shed, always served
- **Standard**: Shed only under extreme pressure
- **Sheddable**: First to be dropped when capacity is exhausted

### InferencePool

Defined by platform operators. Manages a pool of model-serving pods and the endpoint selection logic.

```yaml
apiVersion: inference.networking.x-k8s.io/v1alpha2
kind: InferencePool
metadata:
  name: gpu-pool
spec:
  targetPortNumber: 8000
  selector:
    matchLabels:
      app: vllm
  extensionRef:
    name: endpoint-picker       # ESE sidecar for intelligent routing
```

## Intelligent Routing

```mermaid
graph LR
    subgraph factors["Routing Decision Factors"]
        kv["KV Cache<br/>Utilization"]
        lora["LoRA Adapter<br/>Affinity"]
        gpu["GPU Memory<br/>Pressure"]
        queue["Queue<br/>Depth"]
        crit["Request<br/>Criticality"]
        prefix["Prefix Cache<br/>Awareness"]
    end

    subgraph result["Decision"]
        pick["Best Backend"]
    end

    kv --> pick
    lora --> pick
    gpu --> pick
    queue --> pick
    crit --> pick
    prefix --> pick

    style factors fill:#fff3e0,stroke:#e65100
    style result fill:#e8f5e9,stroke:#2e7d32
```

| Factor | Why It Matters |
|--------|---------------|
| **KV cache utilization** | High KV cache = more context reuse, higher throughput |
| **LoRA adapter affinity** | Route to backend with adapter already loaded (avoids cold-load) |
| **GPU memory pressure** | Avoid backends near OOM |
| **Queue depth** | Avoid backends with long request queues |
| **Request criticality** | Shed low-priority requests before high-priority |
| **Prefix cache awareness** | Route to backend likely holding relevant KV cache entries |

## Model Canary Deployments

```mermaid
graph LR
    subgraph phase1["Phase 1: Canary"]
        p1v1["llama-3.1-70b<br/>95%"]
        p1v2["llama-3.2-90b<br/>5%"]
    end

    subgraph phase2["Phase 2: Shift"]
        p2v1["llama-3.1-70b<br/>50%"]
        p2v2["llama-3.2-90b<br/>50%"]
    end

    subgraph phase3["Phase 3: Rollout"]
        p3v2["llama-3.2-90b<br/>100%"]
    end

    phase1 -->|"validate"| phase2
    phase2 -->|"promote"| phase3

    style phase1 fill:#fff9c4,stroke:#f9a825
    style phase2 fill:#ffe0b2,stroke:#ef6c00
    style phase3 fill:#c8e6c9,stroke:#2e7d32
```

```yaml
# Phase 1: 95/5 canary
targetModels:
  - name: llama-3.1-70b
    weight: 95
  - name: llama-3.2-90b
    weight: 5

# Phase 2: shift traffic
targetModels:
  - name: llama-3.1-70b
    weight: 50
  - name: llama-3.2-90b
    weight: 50

# Phase 3: full rollout
targetModels:
  - name: llama-3.2-90b
    weight: 100
```

Instant rollback by adjusting weights back. No pod restarts needed.

## Rate Limiting for LLM Endpoints

```mermaid
graph TB
    req([Incoming Request])

    subgraph admission["Admission Control"]
        crit_check{Criticality?}
        critical["Critical<br/>Always admit"]
        standard["Standard<br/>Admit if capacity"]
        sheddable["Sheddable<br/>Drop under load"]
    end

    subgraph limiting["Rate Limiting"]
        local["Local Rate Limit<br/>per-pod EnvoyFilter"]
        global["Global Rate Limit<br/>external service"]
    end

    req --> crit_check
    crit_check -->|Critical| critical
    crit_check -->|Standard| standard
    crit_check -->|Sheddable| sheddable
    critical --> local
    standard --> local
    local --> global

    style admission fill:#e3f2fd,stroke:#1565c0
    style limiting fill:#fce4ec,stroke:#c62828
```

1. **Criticality-based admission**: InferenceModel `criticality` provides priority-based admission control. Under load, Sheddable requests are dropped first.
2. **Local rate limiting**: Per-pod Envoy rate limits via `EnvoyFilter`
3. **Global rate limiting**: External rate limit service for cluster-wide token budgets

```yaml
# Example: limit inference requests per client
apiVersion: networking.istio.io/v1
kind: EnvoyFilter
metadata:
  name: inference-rate-limit
spec:
  workloadSelector:
    labels:
      app: vllm
  configPatches:
    - applyTo: HTTP_FILTER
      match:
        context: SIDECAR_INBOUND
      patch:
        operation: INSERT_BEFORE
        value:
          name: envoy.filters.http.local_ratelimit
          typed_config:
            "@type": type.googleapis.com/udpa.type.v1.TypedStruct
            type_url: type.googleapis.com/envoy.extensions.filters.http.local_ratelimit.v3.LocalRateLimit
            value:
              stat_prefix: inference_rate_limit
              token_bucket:
                max_tokens: 10
                tokens_per_fill: 10
                fill_interval: 60s
```

## Observability for AI Workloads

```mermaid
graph LR
    subgraph mesh["Istio Mesh Telemetry"]
        latency["Latency<br/>p50/p95/p99<br/>TTFT + total"]
        rps["Request Rate<br/>per model version"]
        errors["Error Rate<br/>4xx/5xx per model"]
        traces["Distributed Traces<br/>gateway to backend"]
        mtls["mTLS<br/>SPIFFE identity"]
    end

    subgraph targets["Backends"]
        prom["Prometheus"]
        jaeger["Jaeger / Zipkin"]
        grafana["Grafana"]
    end

    latency --> prom
    rps --> prom
    errors --> prom
    traces --> jaeger
    prom --> grafana

    style mesh fill:#ede7f6,stroke:#4527a0
    style targets fill:#e0f2f1,stroke:#00695c
```

| Signal | What You Get |
|--------|-------------|
| **Latency histograms** | p50/p95/p99 per model endpoint (time-to-first-token, total latency) |
| **Request rate** | Requests per second per model version |
| **Error rate** | 4xx/5xx per model (OOM, timeout, overload) |
| **Distributed traces** | Full trace from gateway through inference pool to backend |
| **mTLS** | All model traffic encrypted, SPIFFE identity per pod |

## Enabling the Inference Extension

The Inference Extension is **off by default** in Istio 1.29. To enable:

```yaml
# values-overrides.yaml
istiod:
  pilot:
    env:
      PILOT_ENABLE_ALPHA_GATEWAY_API: "true"
```

Then install the Inference Extension CRDs:

```bash
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api-inference-extension/releases/download/v0.3.0/manifests.yaml
```

## When to Use

| Scenario | Use Inference Extension? |
|----------|------------------------|
| Single model, low traffic | No -- simple HTTPRoute + Service is enough |
| Multiple model versions with canary | Yes -- weighted targetModels |
| GPU-backed inference with LoRA | Yes -- adapter affinity routing |
| Multi-tenant LLM with priorities | Yes -- criticality-based admission |
| Batch embedding jobs | No -- standard Kubernetes Job/Deployment |
