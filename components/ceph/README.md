# Ceph Storage Component

Rook-Ceph provides distributed storage for Kubernetes using Ceph.

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Component Architecture](#component-architecture)
- [Data Flow](#data-flow)
- [Prerequisites](#prerequisites)
- [Configuration](#configuration)
- [Helm Charts](#helm-charts)
- [CSI Drivers](#csi-drivers)
- [Service Accounts & RBAC](#service-accounts--rbac)
- [Object Store (S3)](#object-store-s3)
- [Authentication (Keycloak + STS)](#authentication-keycloak--sts)
- [Performance Tuning](#performance-tuning)
- [Load Balancing](#load-balancing)
- [Monitoring](#monitoring)
- [Disaster Recovery](#disaster-recovery)
- [Usage](#usage)

---

## Architecture Overview

### High-Level Deployment

```mermaid
flowchart TB
    subgraph K8s["Kubernetes Cluster"]
        subgraph ControlPlane["Control Plane"]
            RookOp["Rook Operator"]
            CSI["CSI Drivers"]
        end

        subgraph DataPlane["Data Plane"]
            subgraph Node1["Node 1"]
                MON1["MON"]
                OSD1["OSD"]
                RGW1["RGW"]
            end
            subgraph Node2["Node 2"]
                MON2["MON"]
                OSD2["OSD"]
                RGW2["RGW"]
            end
            subgraph Node3["Node 3"]
                MON3["MON"]
                OSD3["OSD"]
                RGW3["RGW"]
            end
        end

        MGR["MGR (Manager)"]
        MDS["MDS (CephFS)"]
    end

    subgraph Storage["Storage Backend"]
        RADOS["RADOS (Reliable Autonomic Distributed Object Store)"]
    end

    RookOp --> MON1 & MON2 & MON3
    RookOp --> OSD1 & OSD2 & OSD3
    RookOp --> RGW1 & RGW2 & RGW3
    RookOp --> MGR
    RookOp --> MDS

    OSD1 & OSD2 & OSD3 --> RADOS
    MON1 <--> MON2 <--> MON3
```

### Storage Services Architecture

```mermaid
flowchart LR
    subgraph Clients["Client Applications"]
        Spark["Spark/Iceberg"]
        DB["Databases"]
        Apps["Applications"]
    end

    subgraph Services["Ceph Storage Services"]
        RGW["RGW (S3 API)"]
        RBD["RBD (Block)"]
        CephFS["CephFS (File)"]
    end

    subgraph Core["Ceph Core"]
        RADOS["RADOS"]
        subgraph Pools["Storage Pools"]
            DataPool["Data Pool"]
            MetaPool["Metadata Pool"]
        end
    end

    subgraph Physical["Physical Storage"]
        OSD1["OSD 1"]
        OSD2["OSD 2"]
        OSD3["OSD 3"]
    end

    Spark -->|S3 API| RGW
    DB -->|Block Device| RBD
    Apps -->|POSIX| CephFS

    RGW --> RADOS
    RBD --> RADOS
    CephFS --> RADOS

    RADOS --> DataPool
    RADOS --> MetaPool

    DataPool --> OSD1 & OSD2 & OSD3
    MetaPool --> OSD1 & OSD2 & OSD3
```

---

## Component Architecture

### Rook Operator

```mermaid
flowchart TB
    subgraph RookOperator["Rook Operator Pod"]
        Controller["Controller Manager"]
        Webhooks["Admission Webhooks"]

        subgraph Watchers["CRD Watchers"]
            ClusterWatch["CephCluster"]
            PoolWatch["CephBlockPool"]
            FSWatch["CephFilesystem"]
            ObjWatch["CephObjectStore"]
            UserWatch["CephObjectStoreUser"]
        end
    end

    subgraph ManagedResources["Managed Resources"]
        MON["MON Deployments"]
        OSD["OSD Deployments"]
        MGR["MGR Deployment"]
        RGW["RGW Deployments"]
        MDS["MDS Deployments"]
    end

    Controller --> Watchers
    ClusterWatch --> MON & OSD & MGR
    ObjWatch --> RGW
    FSWatch --> MDS
```

### Monitor (MON) Quorum

```mermaid
flowchart LR
    subgraph Quorum["MON Quorum (Paxos Consensus)"]
        MON1["MON 1<br/>(Leader)"]
        MON2["MON 2"]
        MON3["MON 3"]
    end

    subgraph ClusterMap["Cluster Maps"]
        MonMap["Monitor Map"]
        OSDMap["OSD Map"]
        PGMap["PG Map"]
        CRUSHMap["CRUSH Map"]
    end

    MON1 <-->|Consensus| MON2
    MON2 <-->|Consensus| MON3
    MON3 <-->|Consensus| MON1

    MON1 --> ClusterMap
    MON2 --> ClusterMap
    MON3 --> ClusterMap
```

### OSD Data Flow

```mermaid
flowchart TB
    subgraph Client["Client"]
        Write["Write Request"]
    end

    subgraph PrimaryOSD["Primary OSD"]
        Journal1["Journal/WAL"]
        Store1["BlueStore"]
    end

    subgraph ReplicaOSD1["Replica OSD 1"]
        Journal2["Journal/WAL"]
        Store2["BlueStore"]
    end

    subgraph ReplicaOSD2["Replica OSD 2"]
        Journal3["Journal/WAL"]
        Store3["BlueStore"]
    end

    Write -->|1. Send Data| PrimaryOSD
    PrimaryOSD -->|2. Replicate| ReplicaOSD1
    PrimaryOSD -->|2. Replicate| ReplicaOSD2
    ReplicaOSD1 -->|3. ACK| PrimaryOSD
    ReplicaOSD2 -->|3. ACK| PrimaryOSD
    PrimaryOSD -->|4. Commit ACK| Write

    Journal1 --> Store1
    Journal2 --> Store2
    Journal3 --> Store3
```

---

## Data Flow

### S3 Request Flow

```mermaid
sequenceDiagram
    participant App as Application
    participant LB as Load Balancer
    participant RGW as RGW Pod
    participant MON as MON
    participant OSD as OSD

    App->>LB: S3 PUT Request
    LB->>RGW: Forward (Round Robin)
    RGW->>RGW: Authenticate (SigV4/STS)
    RGW->>MON: Get Cluster Map
    MON-->>RGW: Return OSD locations
    RGW->>OSD: Write Object (Primary)
    OSD->>OSD: Replicate to peers
    OSD-->>RGW: Write ACK
    RGW-->>LB: HTTP 200 OK
    LB-->>App: Success
```

### Multipart Upload Flow

```mermaid
sequenceDiagram
    participant App as Application
    participant RGW1 as RGW Pod A
    participant RGW2 as RGW Pod B
    participant RGW3 as RGW Pod C
    participant RADOS as RADOS

    App->>RGW1: InitiateMultipartUpload
    RGW1->>RADOS: Store UploadID metadata
    RGW1-->>App: Return UploadID

    App->>RGW2: UploadPart 1 (with UploadID)
    RGW2->>RADOS: Lookup UploadID
    RGW2->>RADOS: Store Part 1
    RGW2-->>App: ETag Part 1

    App->>RGW3: UploadPart 2 (with UploadID)
    RGW3->>RADOS: Lookup UploadID
    RGW3->>RADOS: Store Part 2
    RGW3-->>App: ETag Part 2

    App->>RGW1: CompleteMultipartUpload
    RGW1->>RADOS: Assemble parts
    RGW1-->>App: Object Created

    Note over RGW1,RGW3: No session stickiness needed<br/>UploadID tracked in RADOS
```

### CSI Volume Provisioning

```mermaid
sequenceDiagram
    participant User as User/Pod
    participant K8s as Kubernetes API
    participant CSI as CSI Provisioner
    participant Rook as Rook Operator
    participant Ceph as Ceph Cluster

    User->>K8s: Create PVC
    K8s->>CSI: Volume provision request
    CSI->>Ceph: Create RBD image
    Ceph-->>CSI: Image created
    CSI->>K8s: Create PV
    K8s->>K8s: Bind PVC to PV
    K8s-->>User: PVC Ready

    User->>K8s: Create Pod with PVC
    K8s->>CSI: Stage volume (node)
    CSI->>Ceph: Map RBD device
    K8s->>CSI: Publish volume (pod)
    CSI-->>K8s: Mount complete
    K8s-->>User: Pod Running
```

---

## Prerequisites

- Minikube cluster with at least 3 nodes (for production-like setup)
- Storage: raw block devices or directories for OSDs
- Minimum resources:

| Component | CPU | Memory | Count |
|-----------|-----|--------|-------|
| Rook Operator | 0.5 | 512Mi | 1 |
| MON | 0.5 | 1Gi | 3 |
| OSD | 1 | 2Gi | 3+ |
| MGR | 0.5 | 512Mi | 1 |
| RGW | 1 | 2Gi | 2+ |
| **Total Min** | **5** | **10Gi** | - |

---

## Configuration

Enable Ceph in `config.yaml`:

```yaml
components:
  ceph:
    enabled: true
    namespace: "rook-ceph"
    chart_repo: "https://charts.rook.io/release"
    operator_chart: "rook-ceph"
    cluster_chart: "rook-ceph-cluster"
    chart_version: "v1.13.0"

    storage:
      use_all_nodes: true
      use_all_devices: false
      directories:
        - path: /var/lib/rook

    object_store:
      enabled: true
      name: "s3-store"
      port: 80
      instances: 2
```

---

## Helm Charts

Rook provides two Helm charts:

```mermaid
flowchart LR
    subgraph Charts["Helm Charts"]
        OpChart["rook-ceph<br/>(Operator Chart)"]
        ClusterChart["rook-ceph-cluster<br/>(Cluster Chart)"]
    end

    subgraph Deploys1["Operator Chart Deploys"]
        Operator["Rook Operator"]
        CSIDriver["CSI Drivers"]
        CRDs["CRDs"]
    end

    subgraph Deploys2["Cluster Chart Deploys"]
        CephCluster["CephCluster CR"]
        StorageClass["StorageClasses"]
        Toolbox["Toolbox Pod"]
    end

    OpChart --> Deploys1
    ClusterChart --> Deploys2
    Deploys1 -->|Must deploy first| Deploys2
```

### Chart.yaml

```yaml
apiVersion: v2
name: rook-ceph
description: Rook-Ceph storage deployment
type: application
version: 1.0.0

dependencies:
  - name: rook-ceph
    version: "v1.13.0"
    repository: "https://charts.rook.io/release"
    alias: operator

  - name: rook-ceph-cluster
    version: "v1.13.0"
    repository: "https://charts.rook.io/release"
    alias: cluster
```

---

## CSI Drivers

### CSI Architecture

```mermaid
flowchart TB
    subgraph ControllerPlugin["CSI Controller (Deployment)"]
        Provisioner["csi-provisioner"]
        Attacher["csi-attacher"]
        Snapshotter["csi-snapshotter"]
        Resizer["csi-resizer"]
        ControllerDriver["cephcsi driver"]
    end

    subgraph NodePlugin["CSI Node (DaemonSet)"]
        NodeRegistrar["node-driver-registrar"]
        NodeDriver["cephcsi driver"]
    end

    subgraph K8s["Kubernetes"]
        PVC["PVC"]
        PV["PV"]
        Pod["Pod"]
    end

    PVC -->|Create| Provisioner
    Provisioner --> ControllerDriver
    ControllerDriver -->|Create Volume| Ceph[(Ceph)]

    Pod -->|Mount| NodeRegistrar
    NodeRegistrar --> NodeDriver
    NodeDriver -->|Map/Mount| Ceph
```

### CSI Configuration

```yaml
csi:
  enableRbdDriver: true
  enableCephfsDriver: true
  kubeletDirPath: /var/lib/kubelet
  provisionerReplicas: 1  # Dev: 1, Prod: 2+
  enableCSISnapshotter: true

  csiRBDProvisionerResource: |
    - name: csi-provisioner
      resource:
        requests:
          memory: 64Mi
          cpu: 50m
        limits:
          memory: 256Mi
          cpu: 200m
```

### Provisioner Replicas

```mermaid
flowchart LR
    subgraph Dev["Development (replicas: 1)"]
        P1["Provisioner<br/>(Active)"]
    end

    subgraph Prod["Production (replicas: 2+)"]
        P2["Provisioner 1<br/>(Leader)"]
        P3["Provisioner 2<br/>(Standby)"]
        P4["Provisioner 3<br/>(Standby)"]
    end

    P2 -->|Leader Election| P3
    P3 -->|Failover| P2
```

---

## Service Accounts & RBAC

Rook **automatically creates** all required service accounts:

| Service Account | Purpose |
|-----------------|---------|
| `rook-ceph-system` | Operator pod |
| `rook-ceph-osd` | OSD pods |
| `rook-ceph-mgr` | Manager pod |
| `rook-ceph-rgw` | RGW pods |
| `rook-csi-rbd-provisioner-sa` | RBD CSI provisioner |
| `rook-csi-rbd-plugin-sa` | RBD CSI node plugin |
| `rook-csi-cephfs-provisioner-sa` | CephFS CSI provisioner |
| `rook-csi-cephfs-plugin-sa` | CephFS CSI node plugin |

**No manual service account creation needed.**

---

## Object Store (S3)

### RGW Architecture

```mermaid
flowchart TB
    subgraph Clients["Clients"]
        Spark["Spark"]
        Iceberg["Iceberg"]
        S3Cli["AWS CLI"]
    end

    subgraph LoadBalancer["Load Balancer"]
        LB["Service/Ingress<br/>(Round Robin)"]
    end

    subgraph RGWPods["RGW Pods (Scalable)"]
        RGW1["RGW 1"]
        RGW2["RGW 2"]
        RGW3["RGW 3"]
    end

    subgraph Pools["Ceph Pools"]
        DataPool["Data Pool<br/>(Replicated/EC)"]
        MetaPool["Metadata Pool<br/>(Replicated)"]
        IndexPool["Index Pool<br/>(Replicated)"]
    end

    Clients --> LB
    LB --> RGW1 & RGW2 & RGW3
    RGW1 & RGW2 & RGW3 --> DataPool & MetaPool & IndexPool
```

### CephObjectStore CR

```yaml
apiVersion: ceph.rook.io/v1
kind: CephObjectStore
metadata:
  name: s3-store
  namespace: rook-ceph
spec:
  metadataPool:
    replicated:
      size: 2
  dataPool:
    replicated:
      size: 2
    # OR erasure coding for large objects
    # erasureCoded:
    #   dataChunks: 4
    #   codingChunks: 2

  gateway:
    port: 80
    securePort: 443
    instances: 2

    resources:
      limits:
        cpu: "4"
        memory: "8Gi"
      requests:
        cpu: "2"
        memory: "4Gi"

    placement:
      podAntiAffinity:
        requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchLabels:
                app: rook-ceph-rgw
            topologyKey: kubernetes.io/hostname
```

---

## Authentication (Keycloak + STS)

### Auth Flow

```mermaid
sequenceDiagram
    participant App as Application
    participant KC as Keycloak
    participant RGW as RGW (STS)
    participant S3 as RGW (S3)

    App->>KC: 1. Authenticate (user/pass or client credentials)
    KC-->>App: 2. JWT Token

    App->>RGW: 3. AssumeRoleWithWebIdentity(JWT)
    RGW->>KC: 4. Validate JWT signature
    KC-->>RGW: 5. Token valid
    RGW->>RGW: 6. Check IAM role policy
    RGW-->>App: 7. Temporary credentials (AccessKey, SecretKey, SessionToken)

    App->>S3: 8. S3 request with temp credentials
    S3-->>App: 9. Success
```

### Configuration

```yaml
# Enable in CephCluster
spec:
  cephConfig:
    global:
      rgw_s3_auth_use_sts: "true"
      rgw_sts_key: "your-sts-signing-key-min-16-characters"
      rgw_s3_auth_use_oidc: "true"
```

### Register OIDC Provider

```bash
radosgw-admin oidc provider create \
  --provider-url="https://keycloak.example.com/realms/myrealm" \
  --client-id="ceph-rgw" \
  --thumbprint="<keycloak-certificate-thumbprint>"
```

### Create IAM Role

```bash
radosgw-admin role create \
  --role-name=keycloak-s3-role \
  --path=/ \
  --assume-role-policy-doc='{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam:::oidc-provider/keycloak.example.com/realms/myrealm"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "keycloak.example.com/realms/myrealm:aud": "ceph-rgw"
        }
      }
    }]
  }'
```

---

## Performance Tuning

### Scaling Guidelines

```mermaid
flowchart LR
    subgraph Workload["Workload Size"]
        Dev["Dev<br/>< 100 req/s"]
        Small["Small<br/>< 1K req/s"]
        Medium["Medium<br/>1K-10K req/s"]
        Large["Large<br/>10K+ req/s"]
    end

    subgraph Config["RGW Config"]
        Dev --> D["1 instance<br/>1 CPU, 2Gi"]
        Small --> S["2 instances<br/>2 CPU, 4Gi"]
        Medium --> M["3-5 instances<br/>4 CPU, 8Gi"]
        Large --> L["5-10+ instances<br/>8 CPU, 16Gi"]
    end
```

### RGW Performance Config

```yaml
spec:
  cephConfig:
    global:
      # Thread pools
      rgw_thread_pool_size: "512"
      rgw_num_async_rados_threads: "128"

      # Connections
      rgw_frontends: "beast port=80 num_threads=128"
      rgw_max_concurrent_requests: "1024"

      # Buffer sizes (for large Iceberg parquet files)
      rgw_put_obj_min_window_size: "16777216"   # 16MB
      rgw_get_obj_max_req_size: "16777216"      # 16MB
```

### Pool PG Calculation

```
PGs = (OSDs × 100) / replicas

Example: 9 OSDs, 3x replication
PGs = (9 × 100) / 3 = 300 → round to 256 (power of 2)
```

### Spark/Iceberg Client Config

```python
spark = SparkSession.builder \
    .config("spark.hadoop.fs.s3a.connection.maximum", "200") \
    .config("spark.hadoop.fs.s3a.threads.max", "64") \
    .config("spark.hadoop.fs.s3a.multipart.size", "64M") \
    .config("spark.hadoop.fs.s3a.fast.upload", "true") \
    .config("spark.hadoop.fs.s3a.fast.upload.buffer", "bytebuffer") \
    .getOrCreate()
```

---

## Load Balancing

### No Session Stickiness Required

```mermaid
flowchart LR
    subgraph Why["Why Stateless Works"]
        A["S3 Protocol<br/>Stateless by design"]
        B["Auth per request<br/>AWS SigV4"]
        C["Multipart tracked<br/>by UploadID in RADOS"]
        D["STS tokens<br/>cluster-wide valid"]
    end

    subgraph Result["Result"]
        R["Round-robin LB<br/>No stickiness needed"]
    end

    A & B & C & D --> Result
```

### Recommended Config

```yaml
apiVersion: v1
kind: Service
metadata:
  name: rgw-lb
spec:
  type: LoadBalancer
  sessionAffinity: None  # Round-robin
  selector:
    app: rook-ceph-rgw
  ports:
    - port: 80
```

### Ingress with Connection Pooling

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: rgw-ingress
  annotations:
    nginx.ingress.kubernetes.io/load-balance: "round_robin"
    nginx.ingress.kubernetes.io/upstream-keepalive-connections: "320"
    nginx.ingress.kubernetes.io/upstream-keepalive-timeout: "60"
```

---

## Monitoring

### Metrics Architecture

```mermaid
flowchart LR
    subgraph Ceph["Ceph Components"]
        MGR["MGR<br/>(Prometheus Module)"]
        RGW["RGW Metrics"]
        OSD["OSD Metrics"]
    end

    subgraph Monitoring["Monitoring Stack"]
        Prom["Prometheus"]
        Graf["Grafana"]
        Alert["Alertmanager"]
    end

    MGR --> Prom
    RGW --> Prom
    OSD --> Prom
    Prom --> Graf
    Prom --> Alert
```

### Key Metrics

| Metric | Query | Alert Threshold |
|--------|-------|-----------------|
| RGW Request Rate | `rate(ceph_rgw_req[5m])` | - |
| RGW Latency (p99) | `histogram_quantile(0.99, rate(ceph_rgw_op_latency_bucket[5m]))` | > 500ms |
| Cluster Health | `ceph_health_status` | != 0 |
| OSD Latency | `ceph_osd_apply_latency_ms` | > 100ms |

### HPA for RGW

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: rgw-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: rook-ceph-rgw-s3-store-a
  minReplicas: 2
  maxReplicas: 10
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
```

---

## Disaster Recovery

### Backup Strategy

```mermaid
flowchart TB
    subgraph Primary["Primary Cluster"]
        RGW1["RGW"]
        Pool1["Data Pools"]
    end

    subgraph Backup["Backup Options"]
        RGWMirror["RGW Multisite<br/>(Async Replication)"]
        S3Sync["rclone/s3cmd<br/>(Bucket Sync)"]
        Snapshot["Ceph Snapshots<br/>(Point-in-time)"]
    end

    subgraph Secondary["Secondary/Backup"]
        S3Backup["S3-compatible<br/>Backup Storage"]
    end

    Primary --> RGWMirror --> Secondary
    Primary --> S3Sync --> Secondary
    Primary --> Snapshot
```

---

## Usage

### Deploy Ceph

```bash
cd /vagrant
./components/ceph/scripts/build.sh
```

### Check Status

```bash
./components/ceph/scripts/status.sh
```

Or manually:
```bash
kubectl -n rook-ceph get pods
kubectl -n rook-ceph get cephcluster
kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph status
```

### Test S3

```bash
./components/ceph/scripts/test-s3.sh
```

### Get S3 Credentials

```bash
# Access key
kubectl -n rook-ceph get secret rook-ceph-object-user-s3-store-admin \
  -o jsonpath='{.data.AccessKey}' | base64 -d && echo

# Secret key
kubectl -n rook-ceph get secret rook-ceph-object-user-s3-store-admin \
  -o jsonpath='{.data.SecretKey}' | base64 -d && echo
```

### Configure AWS CLI

1. Install AWS CLI v2 (not available via apt):

```bash
curl -sL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip
unzip -q awscliv2.zip
sudo ./aws/install
rm -rf aws awscliv2.zip
```

2. Set up port-forward to the RGW service (ClusterIP is not reachable from WSL):

```bash
kubectl -n rook-ceph port-forward svc/rook-ceph-rgw-s3-store 7480:80 &
```

3. Export credentials and endpoint:

```bash
export AWS_ACCESS_KEY_ID=$(kubectl -n rook-ceph get secret rook-ceph-object-user-s3-store-admin -o jsonpath='{.data.AccessKey}' | base64 -d)
export AWS_SECRET_ACCESS_KEY=$(kubectl -n rook-ceph get secret rook-ceph-object-user-s3-store-admin -o jsonpath='{.data.SecretKey}' | base64 -d)
export AWS_ENDPOINT_URL=http://localhost:7480
export AWS_DEFAULT_REGION=us-east-1  # Required: prevents InvalidLocationConstraint error
export AWS_DEFAULT_REGION=us-east-1  # Required: prevents InvalidLocationConstraint error
```

4. Use AWS CLI:

```bash
aws s3 mb s3://my-bucket
aws s3 cp myfile.txt s3://my-bucket/
aws s3 ls s3://my-bucket/
```

### Remove Ceph

```bash
./components/ceph/scripts/destroy.sh
```

---

## File Structure

```
components/ceph/
├── helm/
│   ├── values.yaml             # Configuration overrides
│   └── templates/
│       ├── cephcluster.yaml    # CephCluster CR
│       ├── objectstore.yaml    # S3 gateway + admin user
│       └── storageclass.yaml   # StorageClass definitions
├── scripts/
│   ├── build.sh                # Deploy Ceph
│   ├── destroy.sh              # Remove Ceph
│   ├── status.sh               # Check Ceph health
│   ├── test-s3.sh              # Test S3 connectivity
│   └── create-box.sh           # Create platform box with Ceph
└── README.md                   # This file
```

---

## Notes

- Single-node minikube: Ceph runs in degraded mode (testing only)
- Production: Requires 3+ nodes with dedicated storage devices
- Erasure coding: Better storage efficiency for large Iceberg parquet files
- STS + OIDC: Recommended for multi-tenant or production environments
