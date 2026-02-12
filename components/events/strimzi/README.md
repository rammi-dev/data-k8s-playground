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
- Ceph deployed with `rook-ceph-block` StorageClass (Kafka PVCs)
- `components.strimzi.enabled: true` in config.yaml

## Configuration

Edit `helm/values.yaml` for operator settings, `manifests/kafka-cluster.yaml` for cluster sizing.

## Usage

```bash
# Deploy
./scripts/build.sh

# Destroy
./scripts/destroy.sh
```

## Bootstrap Address

```
events-kafka-kafka-bootstrap.kafka.svc.cluster.local:9092
```

## Storage

Kafka data persists on Ceph RBD via PVC (`rook-ceph-block` StorageClass, 10Gi per broker).

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
├── manifests/
│   └── kafka-cluster.yaml   # Kafka + KafkaNodePool CRs (applied by build.sh after operator)
└── scripts/
    ├── build.sh             # Deploy operator + cluster
    ├── destroy.sh           # Full teardown
    ├── regenerate-rendered.sh
    └── test/
        └── test-kafka.sh    # Test: CRDs, cluster status, produce/consume
```
