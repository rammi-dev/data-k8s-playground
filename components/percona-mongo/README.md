# Percona MongoDB Operator

Percona Operator for MongoDB (PSMDB) automates deployment and management of MongoDB clusters on Kubernetes.

## Table of Contents

- [Storage Concepts](#storage-concepts)
- [Architecture Overview](#architecture-overview)
- [Component Architecture](#component-architecture)
- [Data Flow](#data-flow)
- [Prerequisites](#prerequisites)
- [Configuration](#configuration)
- [Helm Charts](#helm-charts)
- [Storage (PVC)](#storage-pvc)
- [Networking & Ports](#networking--ports)
- [Service Accounts & RBAC](#service-accounts--rbac)
- [TLS Configuration](#tls-configuration)
- [Authentication & Users](#authentication--users)
- [Backup & Recovery](#backup--recovery)
- [S3 Integration](#s3-integration)
- [Monitoring (PMM)](#monitoring-pmm)
- [Operations Runbook](#operations-runbook)
- [Troubleshooting](#troubleshooting)

---

## Storage Concepts

MongoDB on Kubernetes uses **two distinct storage systems** for different purposes:

### Storage Architecture Overview

```mermaid
flowchart TB
    subgraph Purpose["Storage Purpose"]
        direction TB
        BlockStorage["<b>Block Storage (PVC)</b><br/>━━━━━━━━━━━━━━━━━<br/>• MongoDB data files<br/>• WiredTiger storage engine<br/>• Indexes, collections<br/>• Oplog (replication log)<br/>• Fast, low-latency I/O<br/>• Attached to each pod"]

        ObjectStorage["<b>Object Storage (S3)</b><br/>━━━━━━━━━━━━━━━━━<br/>• Backup files<br/>• PITR oplog archives<br/>• Disaster recovery<br/>• Long-term retention<br/>• Cheap, scalable<br/>• Shared across cluster"]
    end

    subgraph Implementation["Implementation"]
        PVC["PersistentVolumeClaim<br/>(StorageClass)"]
        S3["S3-Compatible<br/>(MinIO/Ceph RGW)"]
    end

    BlockStorage --> PVC
    ObjectStorage --> S3
```

### Why Two Storage Types?

| Aspect | Block Storage (PVC) | Object Storage (S3) |
|--------|---------------------|---------------------|
| **Purpose** | Live database operations | Backups & archives |
| **Access Pattern** | Random read/write, low latency | Sequential write, bulk read |
| **Data** | Collections, indexes, oplog | Backup snapshots, PITR logs |
| **Lifecycle** | Persistent with pod | Independent, long retention |
| **Performance** | High IOPS, low latency | High throughput, higher latency |
| **Cost** | Higher (SSD/NVMe) | Lower (object storage) |
| **Redundancy** | Via replica set (3 copies) | Via storage backend |

### Block Storage (PVC + StorageClass)

**What is it?**
- PVC (PersistentVolumeClaim) = Request for storage from Kubernetes
- StorageClass = Defines how storage is provisioned (type, speed, features)

**Why needed for MongoDB?**
```
MongoDB Data Files:
├── WiredTiger.wt          # Storage engine metadata
├── collection-*.wt        # Actual document data
├── index-*.wt             # Index data (B-tree structures)
├── journal/               # Write-ahead log (crash recovery)
└── local/oplog.rs         # Replication oplog
```

MongoDB requires **block storage** because:
1. **Random I/O** - Database reads/writes are random, not sequential
2. **Low latency** - Queries need sub-millisecond storage response
3. **POSIX filesystem** - MongoDB expects a standard filesystem interface
4. **Durability** - Data must survive pod restarts

**StorageClass Selection:**

| StorageClass | Provider | Use Case |
|--------------|----------|----------|
| `standard` | Minikube/local | Development |
| `rook-ceph-block` | Ceph RBD | Production (on-prem) |
| `gp3` | AWS EBS | Production (AWS) |
| `premium-rwo` | GCP PD | Production (GCP) |

### Object Storage (S3)

**What is it?**
- S3 = Simple Storage Service (API standard for object storage)
- Objects = Files with metadata, accessed via HTTP
- Buckets = Containers for objects (like folders)

**Why needed for MongoDB backups?**
```
Backup Storage:
mongodb-backups/
├── 2024-01-15T02:00:00Z/     # Daily backup
│   ├── metadata.json
│   ├── rs0/
│   │   ├── admin.bson.gz
│   │   ├── mydb.users.bson.gz
│   │   └── ...
│
├── pitr/                      # Point-in-Time Recovery
│   ├── oplog_1705276800.gz    # Oplog chunks
│   ├── oplog_1705276810.gz    # (every 10 seconds)
│   └── ...
```

S3 is ideal for backups because:
1. **Scalability** - Unlimited storage, pay-per-use
2. **Durability** - 99.999999999% (11 nines) durability
3. **Cost** - Much cheaper than block storage for large archives
4. **Accessibility** - Can restore to any cluster from anywhere
5. **Versioning** - Keep multiple backup versions

**S3 Options:**

| Provider | Endpoint | Notes |
|----------|----------|-------|
| MinIO | `http://minio:9000` | Self-hosted, simple |
| Ceph RGW | `http://rgw:80` | Integrated with Ceph cluster |
| AWS S3 | `https://s3.amazonaws.com` | Cloud, egress costs |

### How They Work Together

```mermaid
sequenceDiagram
    participant App as Application
    participant Mongo as MongoDB (PVC)
    participant Oplog as Oplog (PVC)
    participant PBM as Backup Agent
    participant S3 as S3 Storage

    Note over App,S3: Normal Operations (PVC only)
    App->>Mongo: Write document
    Mongo->>Mongo: Store in WiredTiger (PVC)
    Mongo->>Oplog: Append to oplog (PVC)
    Mongo-->>App: Acknowledge

    Note over App,S3: Backup Process (PVC → S3)
    PBM->>Mongo: mongodump (read from PVC)
    PBM->>S3: Upload backup files

    Note over App,S3: PITR Streaming (PVC → S3)
    loop Every 10 seconds
        PBM->>Oplog: Read new oplog entries (PVC)
        PBM->>S3: Upload oplog chunk
    end

    Note over App,S3: Disaster Recovery (S3 → PVC)
    PBM->>S3: Download backup
    PBM->>Mongo: mongorestore (write to PVC)
```

### Storage Sizing Guidelines

| Cluster Size | PVC per Node | S3 Bucket |
|--------------|--------------|-----------|
| Dev/Test | 10Gi | 50Gi |
| Small (< 100GB data) | 50Gi | 200Gi |
| Medium (100GB-1TB) | 200Gi | 2TB |
| Large (> 1TB) | 500Gi+ | 5TB+ |

**S3 sizing formula:**
```
S3 Storage = (DB Size × Retention Days × Compression Ratio) + PITR Storage

Example:
- DB Size: 100GB
- Retention: 7 daily backups
- Compression: 0.3 (70% compression)
- PITR: 3 days × 86400 seconds × 1KB/second = ~250GB

S3 = (100GB × 7 × 0.3) + 250GB = 460GB
```

---

## Architecture Overview

### High-Level Deployment (with PMM)

```mermaid
flowchart TB
    subgraph K8s["Kubernetes Cluster"]
        subgraph ControlPlane["Control Plane"]
            Operator["PSMDB Operator"]
        end

        subgraph DataPlane["Data Plane - Replica Set"]
            subgraph RS0["Replica Set rs0"]
                Primary["mongod<br/>PRIMARY"]
                Secondary1["mongod<br/>SECONDARY"]
                Secondary2["mongod<br/>SECONDARY"]
            end
        end

        subgraph Sidecars["Sidecar Containers (per pod)"]
            BackupAgent["Backup Agent<br/>(PBM)"]
            PMMClient["PMM Client"]
        end

        subgraph Storage["Persistent Storage"]
            PVC1["PVC<br/>mongod-data-0"]
            PVC2["PVC<br/>mongod-data-1"]
            PVC3["PVC<br/>mongod-data-2"]
        end

        subgraph Secrets["Secrets"]
            UserSecrets["User Credentials"]
            TLSSecrets["TLS Certificates"]
            S3Secrets["S3 Credentials"]
        end

        subgraph Monitoring["Monitoring Stack"]
            PMM["PMM Server<br/>(Open Source)"]
            Prometheus["Prometheus"]
            Grafana["Grafana"]
        end
    end

    subgraph External["External Storage"]
        S3["S3 / MinIO / Ceph RGW<br/>Backups"]
    end

    Operator -->|manages| RS0
    Primary <-->|replication| Secondary1
    Primary <-->|replication| Secondary2

    Primary --> PVC1
    Secondary1 --> PVC2
    Secondary2 --> PVC3

    BackupAgent -->|backup| S3
    RS0 --> Secrets

    PMMClient -->|metrics + queries| PMM
    PMM --> Grafana
    RS0 -.->|metrics| Prometheus
    Prometheus --> Grafana
```

---

## Sharding Explained

### What is Sharding?

**Sharding** = Horizontal scaling by distributing data across multiple servers (shards).

```mermaid
flowchart LR
    subgraph Without["Without Sharding (Vertical Scaling)"]
        Single["Single Replica Set<br/>━━━━━━━━━━━━━<br/>All 1TB of data<br/>All queries here<br/>Limited by one server"]
    end

    subgraph With["With Sharding (Horizontal Scaling)"]
        Shard1["Shard 1<br/>━━━━━━━━<br/>Users A-M<br/>~333GB"]
        Shard2["Shard 2<br/>━━━━━━━━<br/>Users N-S<br/>~333GB"]
        Shard3["Shard 3<br/>━━━━━━━━<br/>Users T-Z<br/>~333GB"]
    end

    Single -->|"Hit limits?"| With
```

### Why Use Sharding?

| Problem | Sharding Solution |
|---------|-------------------|
| **Data too large** for one server | Split data across shards |
| **Too many queries** for one server | Distribute query load |
| **Write bottleneck** | Parallel writes to different shards |
| **Geographic distribution** | Shards in different regions |

### When to Use Sharding

| Scenario | Recommendation |
|----------|----------------|
| < 100GB data, < 10K ops/sec | **Replica Set** (no sharding) |
| 100GB - 1TB data | Consider sharding |
| > 1TB data or > 50K ops/sec | **Sharding recommended** |
| Need geographic distribution | Sharding with zone awareness |

### Sharding Components

```mermaid
flowchart TB
    subgraph Client["Application"]
        App["MongoDB Driver"]
    end

    subgraph Routers["Query Routers (mongos)"]
        Mongos1["mongos"]
        Mongos2["mongos"]
    end

    subgraph Config["Config Servers (metadata)"]
        direction TB
        ConfigRS["Config Replica Set<br/>━━━━━━━━━━━━━━━━━<br/>• Chunk mappings<br/>• Shard locations<br/>• Collection metadata"]
    end

    subgraph Shards["Data Shards"]
        direction TB
        Shard1["Shard 1 (Replica Set)<br/>━━━━━━━━━━━━━━━━━<br/>Chunks: A-M"]
        Shard2["Shard 2 (Replica Set)<br/>━━━━━━━━━━━━━━━━━<br/>Chunks: N-Z"]
    end

    App --> Mongos1 & Mongos2
    Mongos1 & Mongos2 -->|"Where is data?"| ConfigRS
    Mongos1 & Mongos2 -->|"Query/Write"| Shard1 & Shard2
```

| Component | Purpose | Count |
|-----------|---------|-------|
| **mongos** | Query router, no data storage | 2+ (stateless, scalable) |
| **Config RS** | Stores metadata, chunk mappings | 3 (replica set) |
| **Shard** | Stores actual data, each is a replica set | 2+ (add as needed) |

### Shard Key Selection

The **shard key** determines how data is distributed:

```mermaid
flowchart LR
    subgraph ShardKey["Shard Key Examples"]
        direction TB
        Good["✅ Good Keys<br/>━━━━━━━━━━━━<br/>• user_id (high cardinality)<br/>• order_date + customer_id<br/>• hashed _id"]
        Bad["❌ Bad Keys<br/>━━━━━━━━━━━━<br/>• country (low cardinality)<br/>• created_at (monotonic)<br/>• status (few values)"]
    end
```

| Shard Key Type | Pros | Cons |
|----------------|------|------|
| **Hashed** | Even distribution | No range queries |
| **Ranged** | Range queries work | Can create hotspots |
| **Compound** | Flexible queries | More complex |

### Sharding in Percona Operator

```yaml
spec:
  sharding:
    enabled: true

    # Config servers (metadata)
    configsvrReplSet:
      size: 3
      volumeSpec:
        persistentVolumeClaim:
          resources:
            requests:
              storage: 5Gi

    # Query routers
    mongos:
      size: 2
      resources:
        limits:
          cpu: "1"
          memory: "1G"

  # Data shards (each is a replica set)
  replsets:
    - name: rs0
      size: 3
      volumeSpec:
        persistentVolumeClaim:
          resources:
            requests:
              storage: 50Gi

    - name: rs1
      size: 3
      volumeSpec:
        persistentVolumeClaim:
          resources:
            requests:
              storage: 50Gi
```

### Sharded Cluster Architecture (Full)

```mermaid
flowchart TB
    subgraph Cluster["Sharded MongoDB Cluster"]
        subgraph Mongos["Mongos Routers"]
            Router1["mongos"]
            Router2["mongos"]
        end

        subgraph ConfigRS["Config Server RS"]
            Cfg1["mongod<br/>config"]
            Cfg2["mongod<br/>config"]
            Cfg3["mongod<br/>config"]
        end

        subgraph Shard1["Shard 1 RS"]
            S1P["PRIMARY"]
            S1S1["SECONDARY"]
            S1S2["SECONDARY"]
        end

        subgraph Shard2["Shard 2 RS"]
            S2P["PRIMARY"]
            S2S1["SECONDARY"]
            S2S2["SECONDARY"]
        end
    end

    Client["Application"] --> Router1 & Router2
    Router1 & Router2 --> ConfigRS
    Router1 & Router2 --> Shard1 & Shard2

    Cfg1 <--> Cfg2 <--> Cfg3
    S1P <--> S1S1 <--> S1S2
    S2P <--> S2S1 <--> S2S2
```

---

## Component Architecture

### Operator Components

```mermaid
flowchart TB
    subgraph Operator["PSMDB Operator"]
        Controller["Controller Manager"]

        subgraph Watchers["CRD Watchers"]
            ClusterWatch["PerconaServerMongoDB"]
            BackupWatch["PerconaServerMongoDBBackup"]
            RestoreWatch["PerconaServerMongoDBRestore"]
        end

        subgraph Reconcilers["Reconciliation Loops"]
            ClusterReconciler["Cluster Reconciler"]
            BackupReconciler["Backup Reconciler"]
            RestoreReconciler["Restore Reconciler"]
        end
    end

    subgraph ManagedResources["Managed Kubernetes Resources"]
        STS["StatefulSets<br/>(mongod pods)"]
        SVC["Services<br/>(headless, exposed)"]
        SEC["Secrets<br/>(users, TLS)"]
        CM["ConfigMaps<br/>(mongodb.conf)"]
        PDB["PodDisruptionBudgets"]
        Jobs["Jobs<br/>(backup, restore)"]
    end

    Controller --> Watchers
    ClusterWatch --> ClusterReconciler
    BackupWatch --> BackupReconciler
    RestoreWatch --> RestoreReconciler

    ClusterReconciler --> STS & SVC & SEC & CM & PDB
    BackupReconciler --> Jobs
    RestoreReconciler --> Jobs
```

### Pod Architecture

```mermaid
flowchart LR
    subgraph Pod["MongoDB Pod"]
        subgraph Containers["Containers"]
            Mongod["mongod<br/>(main)"]
            BackupAgent["backup-agent<br/>(PBM)"]
            PMM["pmm-client<br/>(optional)"]
        end

        subgraph Volumes["Volumes"]
            DataVol["mongod-data<br/>(PVC)"]
            TLSVol["tls-certs<br/>(Secret)"]
            ConfigVol["config<br/>(ConfigMap)"]
        end
    end

    Mongod --> DataVol
    Mongod --> TLSVol
    Mongod --> ConfigVol
    BackupAgent --> DataVol
```

---

## Data Flow

### Write Path

```mermaid
sequenceDiagram
    participant App as Application
    participant Pri as PRIMARY
    participant Sec1 as SECONDARY 1
    participant Sec2 as SECONDARY 2
    participant Oplog as Oplog

    App->>Pri: Write Operation
    Pri->>Pri: Apply to Data
    Pri->>Oplog: Write to Oplog
    Pri-->>App: Acknowledge (w:1)

    par Replication
        Pri->>Sec1: Replicate Oplog
        Pri->>Sec2: Replicate Oplog
    end

    Sec1->>Sec1: Apply Oplog Entry
    Sec2->>Sec2: Apply Oplog Entry

    Note over Pri,Sec2: With w:majority, wait for replication ACK
```

### Backup Flow

```mermaid
sequenceDiagram
    participant User as User/CronJob
    participant Op as Operator
    participant PBM as Backup Agent (PBM)
    participant Mongo as MongoDB
    participant S3 as S3/MinIO

    User->>Op: Create PerconaServerMongoDBBackup CR
    Op->>PBM: Trigger backup
    PBM->>Mongo: Lock writes (logical backup)
    PBM->>Mongo: mongodump
    Mongo-->>PBM: Data stream
    PBM->>S3: Upload backup files
    S3-->>PBM: Upload complete
    PBM->>Mongo: Unlock writes
    PBM-->>Op: Backup complete
    Op->>Op: Update CR status
```

### PITR (Point-in-Time Recovery) Flow

```mermaid
sequenceDiagram
    participant PBM as Backup Agent
    participant Mongo as MongoDB Oplog
    participant S3 as S3/MinIO

    loop Every 10 seconds (configurable)
        PBM->>Mongo: Read new oplog entries
        Mongo-->>PBM: Oplog data
        PBM->>PBM: Compress (gzip)
        PBM->>S3: Upload oplog chunk
    end

    Note over PBM,S3: Continuous oplog streaming<br/>enables restore to any point in time
```

---

## Prerequisites

| Requirement | Minimum | Recommended | Notes |
|-------------|---------|-------------|-------|
| Kubernetes | v1.26+ | v1.28+ | |
| CPU | 1 core/pod | 2 cores/pod | Per MongoDB node |
| Memory | 2Gi/pod | 4Gi/pod | Per MongoDB node |
| Storage | 10Gi/pod | 50Gi+/pod | SSD recommended |
| StorageClass | RWO support | | `standard` on minikube |
| S3 Storage | Required | | For backups (MinIO/Ceph RGW) |

---

## Configuration

### config.yaml Integration

```yaml
components:
  percona-mongo:
    enabled: true
    namespace: "percona-mongo"
    chart_repo: "https://percona.github.io/percona-helm-charts/"
    operator_chart: "psmdb-operator"
    operator_version: "1.16.0"

    cluster:
      name: "mongodb"
      mongodb_version: "7.0.8-5"
      replset_size: 3

    storage:
      class: "standard"
      size: "10Gi"

    backup:
      enabled: true
      s3_endpoint: "http://minio.minio:9000"
      s3_bucket: "mongodb-backups"
      schedule: "0 2 * * *"
      retention: 7
```

---

## Helm Charts

### Chart Dependencies

```mermaid
flowchart LR
    subgraph Charts["Helm Charts"]
        OpChart["psmdb-operator<br/>(Operator Chart)"]
        DBChart["psmdb-db<br/>(Database Chart)<br/>(optional)"]
    end

    subgraph Deploys1["Operator Chart Deploys"]
        Operator["Operator Deployment"]
        CRDs["CRDs"]
        RBAC["RBAC Resources"]
    end

    subgraph Deploys2["Database Chart Deploys"]
        Cluster["PerconaServerMongoDB CR"]
        Secrets["Secrets"]
    end

    OpChart --> Deploys1
    DBChart --> Deploys2
    Deploys1 -->|"Required first"| Deploys2
```

### Chart.yaml

```yaml
apiVersion: v2
name: percona-mongo
description: Percona MongoDB deployment
type: application
version: 1.0.0

dependencies:
  - name: psmdb-operator
    version: "1.16.0"
    repository: "https://percona.github.io/percona-helm-charts/"
    alias: operator
```

---

## Storage (PVC)

### PVC Architecture

```mermaid
flowchart TB
    subgraph StorageClass["StorageClass"]
        SC["standard<br/>(minikube default)"]
    end

    subgraph PVCs["PersistentVolumeClaims"]
        PVC0["mongod-data-mongodb-rs0-0<br/>10Gi RWO"]
        PVC1["mongod-data-mongodb-rs0-1<br/>10Gi RWO"]
        PVC2["mongod-data-mongodb-rs0-2<br/>10Gi RWO"]
    end

    subgraph Pods["MongoDB Pods"]
        Pod0["mongodb-rs0-0"]
        Pod1["mongodb-rs0-1"]
        Pod2["mongodb-rs0-2"]
    end

    SC -->|provisions| PVC0 & PVC1 & PVC2
    PVC0 --> Pod0
    PVC1 --> Pod1
    PVC2 --> Pod2
```

### PVC Configuration

```yaml
spec:
  replsets:
    - name: rs0
      size: 3
      volumeSpec:
        persistentVolumeClaim:
          storageClassName: standard  # or rook-ceph-block
          accessModes:
            - ReadWriteOnce
          resources:
            requests:
              storage: 10Gi
```

### Storage Recommendations

| Workload | Storage Size | Storage Class | IOPS |
|----------|--------------|---------------|------|
| Dev/Test | 10Gi | standard | Low |
| Small Prod | 50Gi | rook-ceph-block | Medium |
| Large Prod | 200Gi+ | rook-ceph-block (SSD) | High |

---

## Networking & Ports

### Port Reference

| Port | Protocol | Component | Purpose |
|------|----------|-----------|---------|
| 27017 | TCP | mongod | MongoDB client connections |
| 27018 | TCP | mongod | MongoDB replication (internal) |
| 27019 | TCP | mongod | MongoDB sharding (config servers) |
| 9216 | TCP | mongodb-exporter | Prometheus metrics |
| 42000 | TCP | PMM Client | PMM agent |

### Service Architecture

```mermaid
flowchart TB
    subgraph Services["Kubernetes Services"]
        HeadlessSVC["mongodb-rs0<br/>(Headless)<br/>ClusterIP: None"]
        ExposedSVC["mongodb-rs0-exposed<br/>(ClusterIP/LoadBalancer)"]
    end

    subgraph Pods["MongoDB Pods"]
        Pod0["mongodb-rs0-0<br/>:27017"]
        Pod1["mongodb-rs0-1<br/>:27017"]
        Pod2["mongodb-rs0-2<br/>:27017"]
    end

    subgraph DNS["DNS Records"]
        DNS0["mongodb-rs0-0.mongodb-rs0"]
        DNS1["mongodb-rs0-1.mongodb-rs0"]
        DNS2["mongodb-rs0-2.mongodb-rs0"]
    end

    HeadlessSVC --> Pod0 & Pod1 & Pod2
    ExposedSVC -->|round-robin| Pod0 & Pod1 & Pod2
    DNS0 --> Pod0
    DNS1 --> Pod1
    DNS2 --> Pod2
```

### Service Configuration

```yaml
spec:
  replsets:
    - name: rs0
      expose:
        enabled: true
        exposeType: ClusterIP  # or LoadBalancer, NodePort

      # For external access via LoadBalancer
      # exposeType: LoadBalancer
      # loadBalancerSourceRanges:
      #   - 10.0.0.0/8
```

### Connection Strings

```bash
# Internal (within cluster)
mongodb://userAdmin:password@mongodb-rs0-0.mongodb-rs0.percona-mongo.svc.cluster.local:27017,mongodb-rs0-1.mongodb-rs0.percona-mongo.svc.cluster.local:27017,mongodb-rs0-2.mongodb-rs0.percona-mongo.svc.cluster.local:27017/admin?replicaSet=rs0

# Via Service
mongodb://userAdmin:password@mongodb-rs0.percona-mongo.svc.cluster.local:27017/admin?replicaSet=rs0

# Port-forward (dev)
mongodb://userAdmin:password@localhost:27017/admin?replicaSet=rs0
```

---

## Service Accounts & RBAC

### Service Accounts Created

```mermaid
flowchart TB
    subgraph ServiceAccounts["Service Accounts"]
        OpSA["psmdb-operator<br/>(operator pod)"]
        ClusterSA["mongodb<br/>(mongod pods)"]
    end

    subgraph Roles["Cluster Roles"]
        OpRole["psmdb-operator<br/>(full cluster access)"]
        ClusterRole["psmdb-cluster<br/>(namespace scoped)"]
    end

    subgraph Permissions["Key Permissions"]
        P1["Create/Update StatefulSets"]
        P2["Manage Secrets"]
        P3["Create Services"]
        P4["Watch CRDs"]
    end

    OpSA --> OpRole
    ClusterSA --> ClusterRole
    OpRole --> P1 & P2 & P3 & P4
```

### RBAC Resources

| Resource | Type | Purpose |
|----------|------|---------|
| `psmdb-operator` | ServiceAccount | Operator pod identity |
| `psmdb-operator` | ClusterRole | Operator permissions |
| `psmdb-operator` | ClusterRoleBinding | Bind SA to role |
| `mongodb` | ServiceAccount | MongoDB pod identity |

### Custom RBAC (Optional)

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: mongodb-app-access
  namespace: percona-mongo
rules:
  - apiGroups: [""]
    resources: ["secrets"]
    resourceNames: ["mongodb-secrets"]
    verbs: ["get"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: app-mongodb-binding
  namespace: percona-mongo
subjects:
  - kind: ServiceAccount
    name: my-app
    namespace: my-app-namespace
roleRef:
  kind: Role
  name: mongodb-app-access
  apiGroup: rbac.authorization.k8s.io
```

---

## TLS Configuration

### TLS Architecture

```mermaid
flowchart TB
    subgraph CertManager["Certificate Management"]
        CA["CA Certificate<br/>(self-signed or external)"]
        ServerCert["Server Certificate<br/>(mongod)"]
        ClientCert["Client Certificate<br/>(applications)"]
    end

    subgraph Secrets["Kubernetes Secrets"]
        CASecret["mongodb-ssl-ca<br/>(ca.crt)"]
        ServerSecret["mongodb-ssl<br/>(tls.crt, tls.key)"]
        InternalSecret["mongodb-ssl-internal<br/>(internal communication)"]
    end

    subgraph Pods["MongoDB Pods"]
        Mongod["mongod<br/>--tlsMode requireTLS"]
    end

    CA -->|signs| ServerCert
    CA -->|signs| ClientCert
    CA --> CASecret
    ServerCert --> ServerSecret
    ServerSecret --> Mongod
    CASecret --> Mongod
```

### TLS Modes

| Mode | Description | Use Case |
|------|-------------|----------|
| `disabled` | No TLS | Dev only (not recommended) |
| `allowTLS` | TLS optional | Migration period |
| `preferTLS` | TLS preferred | Transition |
| `requireTLS` | TLS mandatory | Production |

### TLS Configuration

```yaml
spec:
  # TLS for external client connections
  tls:
    mode: requireTLS

    # Option 1: Operator generates self-signed certs
    # (default, no additional config needed)

    # Option 2: Provide your own certificates
    # certSecret: my-mongodb-tls
    # CASecret: my-mongodb-ca

  # TLS for internal replication
  replsets:
    - name: rs0
      configuration: |
        net:
          tls:
            mode: requireTLS
```

### Generate TLS Certificates (Manual)

```bash
# Create CA
openssl genrsa -out ca.key 4096
openssl req -x509 -new -nodes -key ca.key -sha256 -days 3650 \
  -out ca.crt -subj "/CN=MongoDB CA"

# Create server certificate
openssl genrsa -out server.key 4096
openssl req -new -key server.key -out server.csr \
  -subj "/CN=*.mongodb-rs0.percona-mongo.svc.cluster.local"
openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key \
  -CAcreateserial -out server.crt -days 365

# Create Kubernetes secrets
kubectl create secret generic mongodb-ssl \
  --from-file=tls.crt=server.crt \
  --from-file=tls.key=server.key \
  -n percona-mongo

kubectl create secret generic mongodb-ssl-ca \
  --from-file=ca.crt=ca.crt \
  -n percona-mongo
```

### cert-manager Integration

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: mongodb-server-cert
  namespace: percona-mongo
spec:
  secretName: mongodb-ssl
  issuerRef:
    name: mongodb-ca-issuer
    kind: Issuer
  commonName: mongodb
  dnsNames:
    - "*.mongodb-rs0.percona-mongo.svc.cluster.local"
    - "*.mongodb-rs0.percona-mongo.svc"
    - "mongodb-rs0.percona-mongo.svc.cluster.local"
  usages:
    - server auth
    - client auth
```

---

## Authentication & Users

### Built-in Users

| User | Purpose | Roles |
|------|---------|-------|
| `userAdmin` | User management | `userAdminAnyDatabase` |
| `clusterAdmin` | Cluster operations | `clusterAdmin` |
| `clusterMonitor` | Monitoring read | `clusterMonitor` |
| `backup` | Backup operations | `backup`, `restore` |

### User Secrets

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: mongodb-secrets
  namespace: percona-mongo
type: Opaque
stringData:
  MONGODB_BACKUP_USER: backup
  MONGODB_BACKUP_PASSWORD: "secureBackupPassword123!"
  MONGODB_CLUSTER_ADMIN_USER: clusterAdmin
  MONGODB_CLUSTER_ADMIN_PASSWORD: "secureClusterPassword123!"
  MONGODB_CLUSTER_MONITOR_USER: clusterMonitor
  MONGODB_CLUSTER_MONITOR_PASSWORD: "secureMonitorPassword123!"
  MONGODB_USER_ADMIN_USER: userAdmin
  MONGODB_USER_ADMIN_PASSWORD: "secureUserAdminPassword123!"
```

### Create Application User

```javascript
// Connect as userAdmin
use admin
db.createUser({
  user: "myapp",
  pwd: "myAppPassword123",
  roles: [
    { role: "readWrite", db: "myappdb" }
  ]
})
```

---

## Backup & Recovery

### Backup Architecture

```mermaid
flowchart TB
    subgraph BackupTypes["Backup Types"]
        Logical["Logical Backup<br/>(mongodump)"]
        Physical["Physical Backup<br/>(file copy)"]
        PITR["PITR<br/>(oplog streaming)"]
    end

    subgraph Storage["Backup Storage"]
        S3["S3/MinIO"]
        Azure["Azure Blob"]
        GCS["Google Cloud Storage"]
    end

    subgraph Schedule["Backup Schedule"]
        Daily["Daily Full Backup<br/>(cron: 0 2 * * *)"]
        Continuous["Continuous PITR<br/>(every 10s)"]
    end

    Logical --> S3 & Azure & GCS
    Physical --> S3 & Azure & GCS
    PITR --> S3 & Azure & GCS

    Daily --> Logical
    Continuous --> PITR
```

### Backup Configuration

```yaml
spec:
  backup:
    enabled: true
    image: percona/percona-backup-mongodb:2.4.1

    # PITR (Point-in-Time Recovery)
    pitr:
      enabled: true
      oplogOnly: false
      compressionType: gzip
      compressionLevel: 6

    # Storage backends
    storages:
      s3-storage:
        type: s3
        s3:
          bucket: mongodb-backups
          credentialsSecret: mongodb-s3-credentials
          region: us-east-1
          endpointUrl: http://minio.minio:9000
          insecureSkipTLSVerify: true  # For MinIO without TLS
          prefix: backups/

    # Scheduled backups
    tasks:
      - name: daily-backup
        enabled: true
        schedule: "0 2 * * *"
        keep: 7
        storageName: s3-storage
        compressionType: gzip
        type: logical

      - name: weekly-full
        enabled: true
        schedule: "0 3 * * 0"
        keep: 4
        storageName: s3-storage
        type: physical
```

### Backup Types Comparison

| Type | Speed | Size | Cross-Version | Use Case |
|------|-------|------|---------------|----------|
| Logical | Slow | Medium | Yes | Small DBs, migrations |
| Physical | Fast | Large | No | Large DBs, fast restore |
| PITR | Continuous | Small/chunk | Yes | Point-in-time recovery |

### Manual Backup

```yaml
apiVersion: psmdb.percona.com/v1
kind: PerconaServerMongoDBBackup
metadata:
  name: backup-20240115-manual
  namespace: percona-mongo
spec:
  clusterName: mongodb
  storageName: s3-storage
  type: logical
  compressionType: gzip
```

### Restore from Backup

```yaml
apiVersion: psmdb.percona.com/v1
kind: PerconaServerMongoDBRestore
metadata:
  name: restore-20240115
  namespace: percona-mongo
spec:
  clusterName: mongodb
  backupName: backup-20240115-manual
```

### Point-in-Time Restore

```yaml
apiVersion: psmdb.percona.com/v1
kind: PerconaServerMongoDBRestore
metadata:
  name: pitr-restore-20240115
  namespace: percona-mongo
spec:
  clusterName: mongodb
  pitr:
    type: date
    date: "2024-01-15T14:30:00Z"
  backupSource:
    storageName: s3-storage
```

---

## S3 Integration

### S3 Connectivity

```mermaid
flowchart LR
    subgraph K8s["Kubernetes"]
        PBM["Backup Agent<br/>(PBM)"]
        Secret["S3 Credentials<br/>Secret"]
    end

    subgraph S3["S3-Compatible Storage"]
        MinIO["MinIO<br/>(internal)"]
        CephRGW["Ceph RGW<br/>(internal)"]
        AWS["AWS S3<br/>(external)"]
    end

    Secret -->|AWS_ACCESS_KEY_ID<br/>AWS_SECRET_ACCESS_KEY| PBM
    PBM -->|http://minio:9000| MinIO
    PBM -->|http://rgw:80| CephRGW
    PBM -->|https://s3.amazonaws.com| AWS
```

### S3 Credentials Secret

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: mongodb-s3-credentials
  namespace: percona-mongo
type: Opaque
stringData:
  AWS_ACCESS_KEY_ID: minioadmin
  AWS_SECRET_ACCESS_KEY: minioadmin123
```

### S3 Storage Options

| Provider | Endpoint | TLS | Notes |
|----------|----------|-----|-------|
| MinIO (internal) | `http://minio.minio:9000` | Optional | Fast, no egress costs |
| Ceph RGW | `http://rook-ceph-rgw-s3-store.rook-ceph:80` | Optional | Integrated storage |
| AWS S3 | `https://s3.amazonaws.com` | Required | External, egress costs |
| GCS | Via interoperability | Required | Requires HMAC keys |

### Using Ceph RGW for Backups

```yaml
spec:
  backup:
    storages:
      ceph-s3:
        type: s3
        s3:
          bucket: mongodb-backups
          credentialsSecret: ceph-s3-credentials
          region: us-east-1
          endpointUrl: http://rook-ceph-rgw-s3-store.rook-ceph:80
          insecureSkipTLSVerify: true
```

---

## Monitoring (PMM)

### What is PMM?

**Percona Monitoring and Management (PMM)** is a **free and open-source** database monitoring solution.

| Aspect | Details |
|--------|---------|
| **License** | AGPL v3 (fully open source) |
| **Cost** | Free (self-hosted) |
| **Source Code** | [github.com/percona/pmm](https://github.com/percona/pmm) |
| **Components** | PMM Server + PMM Client |
| **Databases** | MongoDB, MySQL, PostgreSQL, ProxySQL |

### PMM Architecture

```mermaid
flowchart TB
    subgraph PMMServer["PMM Server (Open Source)"]
        Victoria["VictoriaMetrics<br/>(TSDB)"]
        ClickHouse["ClickHouse<br/>(Query Analytics)"]
        Grafana["Grafana<br/>(Dashboards)"]
        API["PMM API"]
    end

    subgraph MongoDB["MongoDB Pods"]
        Mongod["mongod"]
        PMMClient["pmm-client<br/>(sidecar)"]
        Exporter["mongodb-exporter"]
    end

    PMMClient -->|metrics| Victoria
    PMMClient -->|slow queries| ClickHouse
    Victoria --> Grafana
    ClickHouse --> Grafana
```

### Monitoring Options Comparison

| Option | PMM | Prometheus + Grafana |
|--------|-----|----------------------|
| **License** | AGPL v3 (open source) | Apache 2.0 |
| **Setup** | Single container | Multiple components |
| **MongoDB Dashboards** | Pre-built, optimized | Need to create/import |
| **Query Analytics** | Built-in (QAN) | Not available |
| **Alerting** | Built-in | Via Alertmanager |
| **Best For** | Full observability | Custom metrics stack |

### Metrics Architecture

```mermaid
flowchart LR
    subgraph MongoDB["MongoDB Pods"]
        Mongod["mongod"]
        Exporter["mongodb-exporter<br/>:9216"]
        PMMClient["pmm-client<br/>(optional)"]
    end

    subgraph Monitoring["Monitoring Stack"]
        Prometheus["Prometheus"]
        Grafana["Grafana"]
        PMM["PMM Server<br/>(open source)"]
    end

    Mongod --> Exporter
    Exporter -->|/metrics| Prometheus
    Prometheus --> Grafana
    PMMClient --> PMM
```

### Key Metrics

| Metric | Description | Alert Threshold |
|--------|-------------|-----------------|
| `mongodb_up` | Instance availability | == 0 |
| `mongodb_connections{state="current"}` | Current connections | > 80% of max |
| `mongodb_replset_member_state` | Replica set state | != 1 (PRIMARY) for primary |
| `mongodb_mongod_op_latencies_latency` | Operation latency | p99 > 100ms |
| `mongodb_mongod_storage_freelist_count` | Storage fragmentation | High value |

### Option 1: Prometheus + Grafana (Your Monitoring Stack)

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: mongodb
  namespace: percona-mongo
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: percona-server-mongodb
  endpoints:
    - port: metrics
      interval: 30s
      path: /metrics
```

### Option 2: PMM (Percona Monitoring)

**Deploy PMM Server:**

```bash
# PMM Server is open source - deploy via Helm
helm repo add percona https://percona.github.io/percona-helm-charts/
helm install pmm percona/pmm \
  --namespace monitoring \
  --set platform=kubernetes
```

**Enable PMM Client in MongoDB:**

```yaml
spec:
  pmm:
    enabled: true
    image: percona/pmm-client:2.41.0
    serverHost: pmm.monitoring.svc.cluster.local
    serverUser: admin
```

### PMM Features (All Free)

| Feature | Description |
|---------|-------------|
| **Query Analytics (QAN)** | Slow query analysis, EXPLAIN plans |
| **MongoDB Dashboards** | Pre-built Grafana dashboards |
| **Replica Set Monitoring** | Replication lag, oplog window |
| **Alerting** | Built-in alert rules |
| **Security** | TLS, authentication |
| **Backup Monitoring** | Track backup status |

---

## Operations Runbook

### Connect to MongoDB

```bash
# Get password
kubectl get secret mongodb-secrets -n percona-mongo \
  -o jsonpath='{.data.MONGODB_USER_ADMIN_PASSWORD}' | base64 -d

# Port forward
kubectl port-forward svc/mongodb-rs0 27017:27017 -n percona-mongo

# Connect
mongosh "mongodb://userAdmin:<password>@localhost:27017/admin?replicaSet=rs0"
```

### Scale Replica Set

```bash
kubectl patch psmdb mongodb -n percona-mongo \
  --type='json' -p='[{"op": "replace", "path": "/spec/replsets/0/size", "value": 5}]'
```

### Check Cluster Status

```bash
# Cluster status
kubectl get psmdb -n percona-mongo

# Pod status
kubectl get pods -n percona-mongo -l app.kubernetes.io/instance=mongodb

# Replica set status (inside mongosh)
rs.status()
```

### List Backups

```bash
kubectl get psmdb-backup -n percona-mongo
```

### Trigger Manual Backup

```bash
kubectl apply -f - <<EOF
apiVersion: psmdb.percona.com/v1
kind: PerconaServerMongoDBBackup
metadata:
  name: manual-$(date +%Y%m%d%H%M%S)
  namespace: percona-mongo
spec:
  clusterName: mongodb
  storageName: s3-storage
EOF
```

---

## Troubleshooting

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| Pods Pending | No PVC | Check StorageClass exists |
| Replica set not forming | DNS issues | Check headless service |
| Backup fails | S3 credentials | Verify secret, test connection |
| TLS handshake fails | Certificate mismatch | Regenerate certificates |
| OOMKilled | Memory too low | Increase memory limits |

### Debug Commands

```bash
# Operator logs
kubectl logs -l app.kubernetes.io/name=psmdb-operator -n percona-mongo

# MongoDB logs
kubectl logs mongodb-rs0-0 -c mongod -n percona-mongo

# Backup agent logs
kubectl logs mongodb-rs0-0 -c backup-agent -n percona-mongo

# Describe cluster
kubectl describe psmdb mongodb -n percona-mongo

# Check events
kubectl get events -n percona-mongo --sort-by='.lastTimestamp'
```

### Verify S3 Connectivity

```bash
# Exec into backup agent
kubectl exec -it mongodb-rs0-0 -c backup-agent -n percona-mongo -- sh

# Test S3 connection
pbm config --list
pbm status
```

---

## File Structure

```
components/percona-mongo/
├── README.md                      # This file
├── helm/
│   ├── Chart.yaml                 # Helm dependencies
│   └── values.yaml                # Configuration overrides
├── manifests/
│   ├── namespace.yaml             # Namespace
│   ├── secrets.yaml.template      # User credentials template
│   ├── s3-credentials.yaml.template
│   ├── cluster.yaml               # PerconaServerMongoDB CR
│   ├── backup-schedule.yaml       # Backup configuration
│   └── tls-certificates.yaml      # TLS secrets (optional)
└── scripts/
    ├── build.sh                   # Deploy operator + cluster
    ├── destroy.sh                 # Remove everything
    ├── backup.sh                  # Trigger manual backup
    └── restore.sh                 # Restore from backup
```

---

## Dependencies

```mermaid
flowchart LR
    subgraph Required["Required"]
        Storage["StorageClass<br/>(standard/rook-ceph-block)"]
        S3["S3 Storage<br/>(MinIO/Ceph RGW)"]
    end

    subgraph Optional["Optional"]
        CertManager["cert-manager<br/>(TLS automation)"]
        Monitoring["Prometheus/Grafana<br/>(metrics)"]
        PMM["PMM Server<br/>(Percona monitoring)"]
    end

    PSMDB["Percona MongoDB"]

    Storage --> PSMDB
    S3 --> PSMDB
    CertManager -.-> PSMDB
    Monitoring -.-> PSMDB
    PMM -.-> PSMDB
```

---

## References

- [Percona Operator Documentation](https://docs.percona.com/percona-operator-for-mongodb/)
- [GitHub Repository](https://github.com/percona/percona-server-mongodb-operator)
- [Helm Charts](https://github.com/percona/percona-helm-charts)
- [Backup/Restore Guide](https://docs.percona.com/percona-operator-for-mongodb/backups.html)
- [TLS Configuration](https://docs.percona.com/percona-operator-for-mongodb/TLS.html)
- [MongoDB Manual](https://www.mongodb.com/docs/manual/)
