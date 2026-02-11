# L0 - Design Principles: C4 Level Separation

> Guidelines for deciding what belongs at each C4 abstraction level in this Data Lakehouse architecture.

## Core Rule

| If it's about...           | It belongs at... |
|----------------------------|------------------|
| External interaction       | **L1** System Context |
| Major runtime boundary     | **L2** Container |
| Logical responsibility     | **L3** Component |
| Scaling / topology / infra | **L4** Deployment |

**Key insight:** L2 is for readability and understanding architectural boundaries, not for full runtime fidelity. L4 handles all the operational detail.

## L1 - System Context

**Purpose:** Who interacts with the platform and which external systems surround it.

**Include:**
- Actors (Data Engineer, Data Analyst, Data Scientist, BI Developer, Platform Admin)
- External systems the platform depends on (MinIO, Keycloak, LDAP, Power BI)
- External systems that feed data in (Legacy MinIO, External Airflow, External Data Sources)
- The Data Lakehouse Platform as a single box

**Do NOT include:**
- Internal services (Dremio, Spark, Airflow, etc.)
- Databases (MongoDB, PostgreSQL, Redis)
- Infrastructure details (executors, pods, operators, K8s objects)

## L2 - Container

**Purpose:** What are the major deployable/runnable building blocks, and how do they relate? L2 shows independently significant architectural elements — not every pod or supporting technology.

### What qualifies as an L2 container

**Decision rule:** If it runs as a separate process with its own lifecycle and could be replaced independently, it's a container. If it's a sidecar, internal library, or scaling detail, it's not.

**Include:**
- Each major service as its own container: Dremio, MongoDB, Superset, Spark, Airflow, JupyterHub
- Relationships between containers (e.g., Dremio -> MongoDB, Superset -> Dremio)
- Relationships to external systems (e.g., Dremio -> MinIO, MongoDB -> MinIO for backups)
- Technology labels (e.g., "Dremio EE 26.1", "Percona MongoDB 8.0")

**Do NOT include:**
- Executor pods, replica members, ZooKeeper instances
- Backup controllers, CronJobs, operators
- Internal modules of a container (those are L3)
- K8s primitives (StatefulSets, Deployments, PVCs)

### Grouping supporting technologies

Complex systems often include supporting infrastructure (databases, queues, caches). These should be **grouped inside** the container they serve at L2, not shown as separate containers — unless they are shared across multiple systems.

| Container (L2) | Internal support (grouped) | Deployment detail (L4) |
|----------------|---------------------------|------------------------|
| Airflow | PostgreSQL, Redis | Web + Scheduler + Workers, Postgres pod, Redis pod, PVCs, Secrets |
| Superset | Celery, Redis, PostgreSQL | Frontend + backend pods, Celery workers, Redis pod |
| Dremio | — (MongoDB is separate, see below) | Dremio pods, ZooKeeper, NATS |
| MongoDB | — | ReplicaSet, Percona Operator, Backup CronJob |
| JupyterHub | Hub Database | Hub + Proxy + user notebook pods |

**Monitoring is an external system** — it is not an L2 container. The Monitoring Platform (Prometheus, ELK, Grafana, etc.) lives outside the Data Lakehouse boundary. Each L4 container boundary documents its metrics endpoints and log forwarding for the external monitoring to scrape/collect.

**When to promote to separate container:** A supporting technology becomes its own L2 container when it is **independently architecturally significant** — it has its own lifecycle, failure domain, backup strategy, or is consumed by multiple containers. MongoDB is promoted because it has its own operator, backup strategy (PBM), and failure domain, even though Dremio is its only consumer.

**When to keep grouped:** Airflow's PostgreSQL and Redis are internal implementation details — they exist solely to support Airflow, have no independent consumers, and are not architecturally significant. Same for Superset's Redis and PostgreSQL. Mention them in the container description (e.g., "Includes PostgreSQL and Redis for internal state") but don't show them as separate L2 boxes.

### Readability over completeness

Show connections that matter for understanding the architecture, not every internal dependency:
- Show Airflow -> Dremio (executes SQL steps)
- Show Superset -> Dremio (queries for dashboards)
- Do NOT show Airflow -> its own Redis (internal queue detail)
- Do NOT show Superset -> its own PostgreSQL (internal state)

If the diagram gets too crowded, consider sub-system groupings (e.g., "Orchestration subsystem = Airflow + its internal deps"). The goal is that someone unfamiliar with the system can understand the major building blocks at a glance.

### Example

MongoDB is a separate container because it has its own lifecycle (Percona operator), its own backup strategy, and its own failure domain — even though its primary consumer is Dremio.

Airflow's PostgreSQL is NOT a separate container because it exists solely to support Airflow, has no independent consumers, and its lifecycle is tied to Airflow's Helm chart.

## L3 - Component

**Purpose:** Logical structure inside ONE container — the responsibilities and modules that make up a service.

**Include:**
- Logical modules within the container (e.g., Query Coordinator, Execution Engine, Catalog Server)
- Relationships between modules (e.g., Catalog Server External -> Catalog Server for proxying)
- Cross-container relationships from components to other containers (e.g., Query Coordinator -> MongoDB)
- External systems referenced by components (e.g., Execution Engine -> MinIO)

**Do NOT include:**
- Infrastructure (operators, sidecars, init containers)
- Scaling details (replica count, resource limits)
- K8s objects (StatefulSets, Services, PVCs)

**Black box rule:** Not every container needs an L3 decomposition. If a container serves a single well-understood purpose and has no meaningful internal modules to show, leave it as a black box. MongoDB is an example — it stores data and that's it; decomposing it into "WiredTiger" and "Replication" adds no architectural insight at this level.

**Example — Dremio L3:** Query Coordinator (SQL planning, client endpoints), Execution Engine (distributed query execution), Engine Operator (CRD-driven scaling), Catalog Server/Polaris (Iceberg metadata), Catalog Server External (external API), Catalog Services (source management).

**Example — MongoDB:** No L3 view. It's a black box at the component level.

## L4 - Deployment

**Purpose:** How containers are physically deployed and operate at runtime. This is where all runtime and operational complexity lives — what actually runs in your environment, not logical components.

### 1. Focus on runtime/deployable units

L4 shows what actually runs, not logical structure. Units include:
- Pods / containers (StatefulSets, Deployments, DaemonSets)
- Operators and their CRDs
- CronJobs, Jobs
- PVCs, Services (headless, LoadBalancer), Secrets
- Sidecars (backup agents, metrics exporters)
- Resource requests/limits, security context (non-root, seccomp, capabilities)

Components inside containers are **not shown** unless they map to separate deployable units.

### 2. Use deployment boundaries for multi-unit containers

If a container consists of multiple runtime units, group them in a boundary labeled with the logical container name. The boundary shows all units that together implement that container.

```
[MongoDB Container Boundary]
  ├─ Primary Pod
  ├─ Secondary Pod x2
  ├─ Arbiter Pod
  ├─ Percona Operator
  └─ PVCs / Secrets
```

### 3. Include infrastructure that matters

Include supporting runtime services that are operationally relevant:
- Message queues (Redis, Kafka)
- Databases (PostgreSQL, MongoDB)
- Storage (PVCs, object storage)
- Backup jobs or operators

Everything that was intentionally hidden at L2 for readability appears here:
- Airflow: Webserver + Scheduler + Triggerer + Workers, PostgreSQL pod, Redis pod, PVCs, Secrets
- Superset: Frontend + backend deployments, Celery workers, Redis pod, PostgreSQL pod
- MongoDB: StatefulSet with 3 replicas, Percona operator, PBM backup CronJob, headless Services, PVCs, TLS config
- Dremio: Master + Executor StatefulSets, ZooKeeper, NATS, Engine Operator

Do **not** include infrastructure used internally by a container unless it affects deployment or scaling.

### 4. Show multiplicity and HA patterns

- Represent replica counts with `[n]` or similar notation (e.g., `StatefulSet (3 replicas)`)
- Indicate high-availability relationships (Primary → Secondary → Arbiter, Master → Worker)
- Include load balancers / services that connect to pods

### 5. Abstract when necessary

If the L4 diagram becomes crowded:
- Create a **top-level L4 diagram** showing main container boundaries and connections
- Create **subsystem-level L4 diagrams** for complex containers (Dremio, MongoDB, Airflow)
- Avoid drawing each pod individually if multiplicity notation can communicate the concept

### 6. Reflect operational concerns, not logical structure

**Focus on:** Scaling, failure domains, deployment locations, storage, operators.

**Do NOT include:**
- Internal methods or modules (that's L3)
- Component interactions inside containers (that's L3)
- Business-level relationships (that's L2)
- External actor interactions (that's L1)

### 7. Maintain alignment with L2/L3

- Each L4 boundary should correspond to an L2 container
- L3 components influence L4 only if they map to separate deployable units (e.g., Dremio Execution Engine → Executor pods, Dremio Engine Operator → Operator deployment)

### 8. Document monitoring per boundary

Monitoring is an external system, not an L2 container. Each L4 container boundary should document:
- **Metrics endpoints** exposed by the boundary's pods (e.g., `:9010/metrics`, `:9216/metrics`)
- **Log collection** method (e.g., stdout → external log collector)
- **Exporter sidecars** if any (e.g., `mongodb_exporter` for Prometheus metrics)

This keeps monitoring concerns visible at L4 without polluting L2/L3 with infrastructure that lives outside the platform.

## Quick Reference

| Element                          | L1 | L2 | L3 | L4 |
|----------------------------------|----|----|----|-----|
| Actors (Data Engineer, etc.)     | Y  |    |    |     |
| External systems (MinIO, LDAP)   | Y  | Y  |    |     |
| Containers (Dremio, MongoDB)     |    | Y  |    |     |
| Container relationships          |    | Y  |    |     |
| Internal support (Redis, PG)     |    | mentioned |    | Y   |
| Logical modules (Query Coord.)   |    |    | Y  |     |
| Cross-container from component   |    |    | Y  |     |
| Deployment boundaries            |    |    |    | Y   |
| StatefulSet / Deployment         |    |    |    | Y   |
| Replica count / HA patterns      |    |    |    | Y   |
| PVCs / Secrets / Services        |    |    |    | Y   |
| Operators / CRDs                 |    |    |    | Y   |
| Sidecars (exporters, PBM agent)  |    |    |    | Y   |
| CronJobs / Jobs                  |    |    |    | Y   |
| Resource requests/limits         |    |    |    | Y   |
| Scaling / failure domains        |    |    |    | Y   |
