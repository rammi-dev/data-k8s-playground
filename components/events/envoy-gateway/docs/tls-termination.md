# TLS Termination Strategies

## Overview

When traffic arrives at the Gateway encrypted with TLS, there are two choices: **terminate** (decrypt at the gateway) or **passthrough** (forward encrypted bytes to the backend). The right choice depends on what the gateway needs to do with the traffic.

## Terminate at Gateway

The Gateway decrypts TLS, inspects the plaintext, and forwards to the backend (plaintext or re-encrypted).

```mermaid
graph LR
    C([Client]) -->|"HTTPS<br>(encrypted)"| GW[Gateway]
    GW -->|"decrypt"| GW
    GW -->|"HTTP (plaintext)<br>inside cluster"| BE[Backend Service]

    style GW fill:#4a90d9,color:#fff
    style BE fill:#50c878,color:#fff
```

**When to terminate:**

| Scenario | Why Gateway must decrypt |
|----------|------------------------|
| L7 routing (path, headers) | Encrypted = opaque bytes, can't route `/api` vs `/web` |
| WAF / rate limiting | Security policies need to inspect request body and headers |
| Header injection | Adding `X-Request-ID`, `X-Forwarded-For`, auth headers |
| Certificate management | One wildcard cert at gateway instead of N certs on N backends |
| Response caching / compression | Gateway can only cache or gzip if it can read the response |
| Content-based load balancing | Routing by cookie, header, or path requires decryption |

This is the **common case** — most HTTPRoute and GRPCRoute setups terminate TLS at the Gateway.

## TLS Passthrough

The Gateway reads only the SNI hostname from the TLS handshake and forwards the entire encrypted stream untouched to the backend.

```mermaid
graph LR
    C([Client]) -->|"TLS handshake<br>(SNI: db.example.com)"| GW[Gateway]
    GW -->|"encrypted stream<br>(not decrypted)"| BE[Backend Service]
    BE -->|"Backend terminates TLS<br>(holds private key)"| BE

    style GW fill:#daa520,color:#fff
    style BE fill:#50c878,color:#fff
```

**When to passthrough:**

| Scenario | Why Gateway must NOT decrypt |
|----------|------------------------------|
| Regulatory / compliance | PCI-DSS, HIPAA — no intermediate decryption point allowed |
| mTLS (client cert auth) | Client authenticates directly to backend, gateway can't impersonate |
| Backend owns the certificate | Backend identity tied to its cert (database TLS, Kafka TLS) |
| Zero-trust architecture | Gateway is not trusted to see plaintext |
| Performance | Skip decrypt + re-encrypt CPU cost |
| Non-HTTP protocols over TLS | PostgreSQL TLS, Kafka TLS — gateway can't parse even if decrypted |

## Re-encryption (Middle Ground)

Gateway terminates client TLS (to inspect/route), then opens a **new** TLS connection to the backend. Best of both worlds at the cost of double encryption.

```mermaid
graph LR
    C([Client]) -->|"HTTPS"| GW[Gateway]
    GW -->|"1. decrypt<br>2. inspect/route<br>3. re-encrypt"| GW
    GW -->|"new TLS connection"| BE[Backend Service]

    style GW fill:#7b68ee,color:#fff
    style BE fill:#50c878,color:#fff
```

Configured via Envoy Gateway's `BackendTrafficPolicy` with backend TLS settings. The tradeoff: double encryption CPU cost and the gateway sees plaintext momentarily in memory.

## Real-World Example: JupyterHub + Keycloak + S3

A common pattern — authenticate users via external Keycloak, then access external S3 storage. TLS termination at the gateway works because the gateway only sits between the browser and the in-cluster service.

```mermaid
sequenceDiagram
    participant U as User Browser
    participant GW as Gateway<br>(TLS termination)
    participant JH as JupyterHub<br>(in cluster)
    participant KC as Keycloak<br>(external)
    participant S3 as MinIO/S3<br>(external)

    U->>GW: GET /hub/login (HTTPS)
    Note over GW: Decrypt TLS<br>Route by path
    GW->>JH: HTTP (plaintext inside cluster)
    JH-->>GW: 302 → keycloak.example.com/auth?client_id=...
    GW-->>U: 302 redirect (HTTPS)
    Note over U: Browser follows redirect<br>(gateway not involved)
    U->>KC: GET /auth/realms/.../auth (direct HTTPS)
    KC-->>U: Login page
    U->>KC: POST credentials
    KC-->>U: 302 → jupyter.example.com/callback?code=abc123
    U->>GW: GET /callback?code=abc123 (HTTPS)
    GW->>JH: Forward callback
    JH->>KC: POST /token — exchange code for tokens (server-to-server TLS)
    KC-->>JH: Access token + ID token
    JH->>S3: S3 API with token-derived creds (server-to-server TLS)
    S3-->>JH: Data
    JH-->>GW: Response
    GW-->>U: HTTPS response
```

**Why termination at the gateway is fine here:**

- **Gateway only handles browser ↔ JupyterHub** — decrypts incoming HTTPS, routes by path, forwards plaintext inside the cluster
- **Keycloak connection is separate** — JupyterHub opens its own outbound TLS connection to Keycloak for token exchange. Gateway is not involved
- **S3 connection is separate** — JupyterHub calls S3 API directly over its own TLS connection. Gateway is not involved
- **No mTLS needed** — authentication is OIDC (application-layer tokens), not TLS client certificates

## Decision Flowchart

```mermaid
graph TD
    Q1{Need to inspect<br>traffic content?}
    Q1 -->|Yes| Q2{Need encryption<br>to backend?}
    Q1 -->|No| Q3{Backend must<br>hold the cert?}

    Q2 -->|Yes| RE[Re-encryption<br>BackendTrafficPolicy + TLS]
    Q2 -->|No| TERM[TLS Termination<br>HTTPRoute / GRPCRoute]

    Q3 -->|Yes| PASS[TLS Passthrough<br>TLSRoute]
    Q3 -->|No| Q4{Protocol is<br>HTTP-based?}

    Q4 -->|Yes| PASS
    Q4 -->|No| TCP[TCPRoute<br>raw forwarding]

    style TERM fill:#50c878,color:#fff
    style RE fill:#7b68ee,color:#fff
    style PASS fill:#daa520,color:#fff
    style TCP fill:#e8744f,color:#fff
```

**Rule of thumb**: If you need to look inside the traffic (route by path, add headers, apply security policies) → terminate at the gateway. If the backend must be the only thing that sees the plaintext → passthrough.
