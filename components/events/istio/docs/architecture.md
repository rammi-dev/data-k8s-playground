# Istio Architecture

## Overview

Istio is a service mesh that intercepts all network traffic between services via sidecar proxies (Envoy). The control plane (istiod) manages configuration, certificates, and service discovery.

```
┌─────────────────────────────────────────────────────────────────┐
│                      CONTROL PLANE                              │
│                                                                 │
│  istiod (istio-system)                                          │
│  ┌────────────┐  ┌──────────────┐  ┌───────────────┐           │
│  │   Pilot    │  │   Citadel    │  │    Galley     │           │
│  │ xDS config │  │ mTLS certs   │  │ config        │           │
│  │ service    │  │ SPIFFE IDs   │  │ validation    │           │
│  │ discovery  │  │ auto-rotate  │  │ webhook       │           │
│  └────────────┘  └──────────────┘  └───────────────┘           │
│                                                                 │
├─────────────────────────────────────────────────────────────────┤
│                       DATA PLANE                                │
│                                                                 │
│  ┌─────────────────┐   ┌─────────────────┐                     │
│  │  Pod A          │   │  Pod B          │                     │
│  │ ┌─────────────┐ │   │ ┌─────────────┐ │                     │
│  │ │ App         │ │   │ │ App         │ │                     │
│  │ └──────┬──────┘ │   │ └──────┬──────┘ │                     │
│  │ ┌──────┴──────┐ │   │ ┌──────┴──────┐ │                     │
│  │ │ Envoy Proxy │◄├───┤►│ Envoy Proxy │ │                     │
│  │ │ (sidecar)   │ │   │ │ (sidecar)   │ │                     │
│  │ └─────────────┘ │   │ └─────────────┘ │                     │
│  └─────────────────┘   └─────────────────┘                     │
│        mTLS encrypted traffic                                   │
│                                                                 │
├─────────────────────────────────────────────────────────────────┤
│                    INGRESS GATEWAY                              │
│                                                                 │
│  Gateway API (istio GatewayClass)                               │
│  ┌──────────────────────────────────────────┐                   │
│  │ Envoy Proxy (auto-provisioned)           │                   │
│  │ TLS termination, routing, load balancing │                   │
│  └──────────────────────────────────────────┘                   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Control Plane: istiod

All control plane components run in a single `istiod` binary:

| Component | Function |
|-----------|----------|
| **Pilot** | Translates mesh config (VirtualService, DestinationRule) into Envoy xDS config. Pushes updates to all sidecars via gRPC. Service discovery from Kubernetes API. |
| **Citadel** | Issues SPIFFE X.509 certificates to every sidecar. Auto-rotates. Enables mutual TLS without app changes. |
| **Galley** | Config validation webhook. Validates CRDs before they are applied. |

## Data Plane: Envoy Sidecars

Every workload pod gets an Envoy sidecar injected via admission webhook:

- **Injection**: Namespace label `istio-injection=enabled` triggers automatic injection
- **Traffic capture**: iptables rules redirect all inbound/outbound traffic through the sidecar
- **mTLS**: Sidecar-to-sidecar traffic is encrypted with SPIFFE certificates
- **Telemetry**: Every request generates metrics, traces, and access logs

## mTLS

This deployment enforces mesh-wide STRICT mTLS via `PeerAuthentication`:

```yaml
apiVersion: security.istio.io/v1
kind: PeerAuthentication
metadata:
  name: default
  namespace: istio-system
spec:
  mtls:
    mode: STRICT
```

All service-to-service traffic within the mesh is encrypted. No plaintext allowed.

## Gateway API Integration

Istio implements the Kubernetes Gateway API as its ingress mechanism:

- **GatewayClass**: `istio` (auto-registered by istiod)
- **Gateway**: Declares listeners (ports, TLS, hostnames)
- **HTTPRoute**: Routing rules (path, header matching, traffic splitting)

This deployment swaps the Gateway API controller from Envoy Gateway to Istio during `build.sh`. Knative's `config-gateway` ConfigMap is patched to use the `istio` GatewayClass.

## Authorization

`AuthorizationPolicy` CRDs control which services can talk to each other:

```yaml
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: allow-knative-system
spec:
  action: ALLOW
  rules:
    - from:
        - source:
            namespaces: ["knative-serving", "knative-eventing", "istio-system"]
```

Without explicit ALLOW rules for Knative system namespaces, scale-from-zero breaks (activator and autoscaler get denied).

## Key CRDs

| CRD | Purpose |
|-----|---------|
| `PeerAuthentication` | mTLS mode (STRICT, PERMISSIVE, DISABLE) |
| `AuthorizationPolicy` | L4/L7 access control per workload |
| `VirtualService` | Traffic routing (retries, timeouts, fault injection, traffic splitting) |
| `DestinationRule` | Load balancing, circuit breaking, connection pool |
| `Gateway` | Ingress listeners (Kubernetes Gateway API) |
| `HTTPRoute` | Ingress routing rules (Kubernetes Gateway API) |
| `EnvoyFilter` | Low-level Envoy config patches (escape hatch) |

## Sidecar vs Ambient Mode

| Aspect | Sidecar (This Deployment) | Ambient |
|--------|---------------------------|---------|
| Proxy location | Per-pod Envoy sidecar | Per-node ztunnel + optional waypoint |
| Resource overhead | ~50MB per pod | Shared per node |
| mTLS | Sidecar handles | ztunnel handles (L4) |
| L7 policies | Always available | Requires waypoint proxy |
| Knative support | Works | Not yet compatible |
| Maturity | Stable | GA since 1.24 |

We use sidecar mode because ambient mode is not yet compatible with Knative's scale-from-zero activator flow.
