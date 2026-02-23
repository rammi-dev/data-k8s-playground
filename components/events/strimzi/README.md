# Strimzi Kafka

Strimzi-managed Apache Kafka cluster for the event-driven playground.

## Chart Versions

| Component | Version |
|-----------|---------|
| Strimzi Operator | 0.50.0 |
| Apache Kafka | 4.1.1 |
| Mode | KRaft (no ZooKeeper) |

## API Reference

- [Strimzi Configuring Guide (0.50.0)](https://strimzi.io/docs/operators/0.50.0/configuring.html) — full CRD schema reference for Kafka, KafkaNodePool, KafkaTopic, KafkaUser

## Components

| Service | Role |
|---------|------|
| Strimzi Operator | Manages Kafka CRDs (Kafka, KafkaNodePool, KafkaTopic, KafkaUser) |
| Kafka (dual-role) | Combined controller + broker node (KRaft consensus) |
| Entity Operator | Topic and user management |

## Prerequisites

- Kubernetes cluster accessible via kubectl
- Ceph deployed with `ceph-block` StorageClass (Kafka PVCs)
- `components.strimzi.enabled: true` in config.yaml

## Configuration

Edit `helm/values.yaml` for operator settings, `scripts/test/manifests/kafka-cluster.yaml` for test cluster sizing.

## Usage

```bash
# Deploy operator
./scripts/build.sh

# Test (creates cluster → validates → tears down)
./scripts/test/test-kafka.sh

# Destroy operator
./scripts/destroy.sh
```

## Bootstrap Address

```
events-kafka-kafka-bootstrap.kafka.svc.cluster.local:9092
```

## Storage

Kafka data persists on Ceph RBD via PVC (`ceph-block` StorageClass, 10Gi per broker).

## File Structure

```
strimzi/
├── README.md
├── deployment/              # Rendered output (.gitignore)
├── docs/
├── helm/
│   ├── Chart.yaml           # Wrapper chart (depends on strimzi-kafka-operator)
│   ├── values.yaml          # Operator configuration
│   └── values-overrides.yaml
└── scripts/
    ├── build.sh             # Deploy operator only
    ├── destroy.sh           # Full teardown
    ├── regenerate-rendered.sh
    └── test/
        ├── manifests/
        │   └── kafka-cluster.yaml   # Test cluster (1 node, KRaft)
        └── test-kafka.sh            # Create → test → destroy
```
