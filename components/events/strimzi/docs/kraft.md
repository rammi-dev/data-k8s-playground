# KRaft — Kafka Without ZooKeeper

## Overview

KRaft (Kafka Raft) replaces ZooKeeper with a built-in Raft consensus protocol for cluster metadata management. ZooKeeper was removed in Kafka 4.0 — KRaft is the only mode.

| Property | Value |
|----------|-------|
| Available since | Kafka 3.3 (preview), 3.6 (production-ready) |
| ZooKeeper removed | Kafka 4.0 |
| Protocol | Raft consensus (adapted for Kafka metadata) |
| Metadata storage | Internal `__cluster_metadata` topic |

## ZooKeeper vs KRaft

```mermaid
graph TB
    subgraph "Old: ZooKeeper Mode"
        ZK[ZooKeeper Ensemble<br>3 separate JVM processes]
        B1Z[Broker 1] ---|metadata sync| ZK
        B2Z[Broker 2] ---|metadata sync| ZK
        B3Z[Broker 3] ---|metadata sync| ZK
        CT[Controller<br>one elected broker]
    end

    subgraph "New: KRaft Mode"
        C1[Controller 1<br>Raft leader] ---|Raft consensus| C2[Controller 2<br>Raft follower]
        C1 ---|Raft consensus| C3[Controller 3<br>Raft follower]
        B1K[Broker 1] ---|fetch metadata| C1
        B2K[Broker 2] ---|fetch metadata| C1
        B3K[Broker 3] ---|fetch metadata| C1
    end

    style ZK fill:#e8744f,color:#fff
    style C1 fill:#50c878,color:#fff
    style C2 fill:#50c878,color:#fff
    style C3 fill:#50c878,color:#fff
```

### What Changed

| Aspect | ZooKeeper | KRaft |
|--------|-----------|-------|
| **Metadata store** | ZooKeeper znodes (separate process, separate protocol) | Internal `__cluster_metadata` topic (same protocol as data) |
| **Consensus** | ZAB (ZooKeeper Atomic Broadcast) | Raft (built into Kafka binary) |
| **Controller election** | ZooKeeper elects one broker as controller | Raft elects a leader among dedicated controller nodes |
| **Metadata propagation** | Controller pushes updates to brokers via RPC | Brokers fetch metadata from the `__cluster_metadata` topic (same as consuming any topic) |
| **Deployment** | Kafka cluster + ZooKeeper cluster (2 separate systems) | Just Kafka (single system) |
| **Startup time** | Minutes (load all metadata from ZK) | Seconds (read local metadata log) |
| **Metadata limit** | ~200K partitions (ZK becomes bottleneck) | Millions of partitions (log-based, no tree traversal) |

## How KRaft Works

### The Metadata Log

All cluster metadata is stored as an append-only log in the `__cluster_metadata` topic — same storage engine as regular Kafka data:

```mermaid
graph LR
    subgraph "__cluster_metadata topic"
        E1["Record 1<br>TopicCreated: orders"]
        E2["Record 2<br>PartitionAssigned: orders-0 → broker 1"]
        E3["Record 3<br>BrokerRegistered: broker-2"]
        E4["Record 4<br>ConfigChanged: retention.ms=604800000"]
        E5["Record 5<br>TopicDeleted: temp-topic"]
    end

    E1 --> E2 --> E3 --> E4 --> E5

    style E1 fill:#4a90d9,color:#fff
    style E2 fill:#4a90d9,color:#fff
    style E3 fill:#4a90d9,color:#fff
    style E4 fill:#4a90d9,color:#fff
    style E5 fill:#4a90d9,color:#fff
```

Every metadata change (topic created, partition reassigned, broker joined, config updated) is appended as a record. Controllers replicate this log via Raft. Brokers consume from it to stay up to date.

### Raft Consensus

The controller quorum uses Raft to agree on the order of metadata records:

```mermaid
sequenceDiagram
    participant C as Client (broker or admin)
    participant L as Controller Leader
    participant F1 as Controller Follower 1
    participant F2 as Controller Follower 2

    C->>L: CreateTopic "orders"
    L->>L: Append to local metadata log
    L->>F1: Replicate record
    L->>F2: Replicate record
    F1-->>L: ACK
    F2-->>L: ACK
    Note over L: Majority (2/3) acknowledged<br>Record is committed
    L-->>C: Topic created successfully

    Note over F1,F2: Brokers fetch the new record<br>and update their in-memory state
```

**Quorum**: With 3 controllers, 2 must agree (majority). This tolerates 1 controller failure. With 5 controllers, 3 must agree (tolerates 2 failures).

### Metadata Version

The metadata version controls which **record types** are allowed in the `__cluster_metadata` log:

```
Kafka 3.6  → metadataVersion: 3.6-IV2  → supports: basic topics, partitions, ACLs
Kafka 3.8  → metadataVersion: 3.8-IV0  → adds: delegation tokens, SCRAM
Kafka 4.0  → metadataVersion: 4.0-IV0  → adds: ZK migration records
Kafka 4.1  → metadataVersion: 4.1-IV1  → adds: share groups, ELR
```

**Why it matters for upgrades:**

```mermaid
graph LR
    A["1. Upgrade binaries<br>Kafka 4.0 → 4.1"] --> B["2. Verify cluster healthy<br>All brokers running"]
    B --> C["3. Bump metadataVersion<br>4.0-IV0 → 4.1-IV1"]
    C --> D["4. New features available<br>share groups, ELR"]

    style A fill:#4a90d9,color:#fff
    style B fill:#daa520,color:#fff
    style C fill:#50c878,color:#fff
    style D fill:#50c878,color:#fff
```

- You can run Kafka 4.1 binaries with `metadataVersion: 4.0-IV0` — it just won't use 4.1 features
- Once you bump the metadata version, **you cannot downgrade** — the log may contain records that older versions can't parse
- This is set in the Kafka CR: `spec.kafka.metadataVersion: "4.1-IV1"`

## Node Roles

In KRaft mode, each Kafka node has one or more roles:

```mermaid
graph TD
    subgraph "Production Layout"
        C1[Controller 1<br>Raft only]
        C2[Controller 2<br>Raft only]
        C3[Controller 3<br>Raft only]
        B1[Broker 1<br>data only]
        B2[Broker 2<br>data only]
        B3[Broker 3<br>data only]
    end

    subgraph "Development Layout (our playground)"
        D1["Dual-Role Node<br>controller + broker<br>(single process)"]
    end

    style C1 fill:#7b68ee,color:#fff
    style C2 fill:#7b68ee,color:#fff
    style C3 fill:#7b68ee,color:#fff
    style B1 fill:#50c878,color:#fff
    style B2 fill:#50c878,color:#fff
    style B3 fill:#50c878,color:#fff
    style D1 fill:#e8744f,color:#fff
```

| Role | What it does | Memory profile |
|------|-------------|----------------|
| **Controller** | Participates in Raft quorum, manages cluster metadata | Low (metadata only, no data) |
| **Broker** | Stores topic partitions, serves produce/consume requests | High (data + page cache) |
| **Dual-role** | Does both in a single process | Combined |

### When to use each

| Layout | When |
|--------|------|
| **Dual-role (1 node)** | Development, testing, single-node playground |
| **Dual-role (3 nodes)** | Small clusters where separate controllers waste resources |
| **Separate roles** | Production — isolate controller from data traffic. A broker OOM or disk full won't kill the controller quorum |

In Strimzi, roles are set via KafkaNodePool:

```yaml
# Our playground — 1 dual-role node
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaNodePool
metadata:
  name: dual-role
spec:
  replicas: 1
  roles:
    - controller
    - broker
```

```yaml
# Production — separate pools
---
kind: KafkaNodePool
metadata:
  name: controllers
spec:
  replicas: 3
  roles:
    - controller     # only Raft, no data
---
kind: KafkaNodePool
metadata:
  name: brokers
spec:
  replicas: 6
  roles:
    - broker         # only data, no Raft
```

## Controller Quorum — How Leader Election Works

```mermaid
stateDiagram-v2
    [*] --> Follower: node starts
    Follower --> Candidate: election timeout<br>(no heartbeat from leader)
    Candidate --> Leader: wins majority vote
    Candidate --> Follower: loses election<br>(another node won)
    Leader --> Follower: discovers higher term<br>(network partition healed)
    Leader --> Leader: sends heartbeats<br>replicates metadata
```

1. All controllers start as **followers**
2. If a follower doesn't hear from the leader within the election timeout, it becomes a **candidate** and requests votes
3. A candidate that receives majority votes becomes the **leader**
4. The leader appends records to the metadata log and replicates to followers
5. If the leader crashes, followers detect the missing heartbeat and start a new election

**Split-brain protection**: Raft guarantees only one leader per term. A leader with a stale term (from a network partition) will step down when it sees a higher term.

## Metadata Snapshots

The metadata log grows forever. To prevent unbounded disk usage, controllers periodically create **snapshots**:

```
Log:      [record 1] [record 2] ... [record 10000] [snapshot @ 10000] [record 10001] ...
                                                         ↑
                                              compact state of all records 1-10000
                                              (old log segments can be deleted)
```

A new broker joining the cluster fetches the latest snapshot + records after it, instead of replaying the entire log from the beginning. This is why KRaft startup is fast — seconds vs minutes with ZooKeeper.

## Strimzi Configuration

In our cluster, KRaft is enabled via annotations on the Kafka CR:

```yaml
apiVersion: kafka.strimzi.io/v1beta2
kind: Kafka
metadata:
  name: events-kafka
  annotations:
    strimzi.io/node-pools: enabled    # use KafkaNodePool for node config
    strimzi.io/kraft: enabled         # KRaft mode (no ZooKeeper)
spec:
  kafka:
    version: 4.1.1
    metadataVersion: "4.1-IV1"        # KRaft metadata protocol version
    listeners:
      - name: plain
        port: 9092
        type: internal
        tls: false
    config:
      # Single-node overrides (no replication possible)
      offsets.topic.replication.factor: 1
      transaction.state.log.replication.factor: 1
      default.replication.factor: 1
      min.insync.replicas: 1
```

Strimzi handles all KRaft internals automatically — `__cluster_metadata` topic creation, controller quorum bootstrap, voter configuration. You just set the annotation and define node pools with roles.
