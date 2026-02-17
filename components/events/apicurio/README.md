# Apicurio Registry

Schema registry for the event-driven playground. Stores and validates Avro, JSON Schema, Protobuf, and OpenAPI schemas used by Kafka producers and consumers.

## Versions

| Component | Version |
|-----------|---------|
| Apicurio Registry | 3.1.7 |
| Storage Backend | KafkaSQL (Kafka topic) |
| API Version | v3 |

## What It Does

Apicurio Registry provides a central store for event schemas, enforcing compatibility rules so producers and consumers agree on data formats:

```
Producer                          Apicurio Registry                    Consumer
   │                                    │                                  │
   ├── register schema ────────────────►│                                  │
   │                                    │◄──────────── fetch schema ───────┤
   ├── serialize (schema ID in header) ─┼──── Kafka ───────────────────────┤
   │                                    │                 deserialize ─────┤
```

- **Producers** register schemas and embed a schema ID in each Kafka message header
- **Consumers** fetch the schema by ID from the registry to deserialize messages
- **Compatibility rules** (BACKWARD, FORWARD, FULL) prevent breaking changes

## Storage: KafkaSQL

Apicurio uses Kafka itself as its backing store (`kafkasql` mode):
- All schema data stored in the `kafkasql-journal` topic (auto-created)
- No external database needed
- Schemas survive pod restarts (data is in Kafka)
- Co-located in the `kafka` namespace with Strimzi

## Prerequisites

- Kubernetes cluster accessible via kubectl
- Strimzi Kafka deployed and ready (`./components/events/strimzi/scripts/build.sh`)
- `components.apicurio.enabled: true` in config.yaml

## Configuration

Edit `config.yaml`:

```yaml
components:
  apicurio:
    enabled: true
    namespace: "kafka"
    image: "docker.io/apicurio/apicurio-registry"
    version: "3.1.7"
    storage: "kafkasql"    # kafkasql | postgresql | mem
    replicas: 1
```

## Usage

```bash
# Deploy
./scripts/build.sh

# Destroy
./scripts/destroy.sh

# Test
./scripts/test/test-apicurio.sh
```

## Endpoints

| Endpoint | URL |
|----------|-----|
| REST API (v3) | `http://apicurio-registry.kafka.svc.cluster.local:8080/apis/registry/v3` |
| Web UI | `http://apicurio-registry.kafka.svc.cluster.local:8080/ui` |
| Health | `http://apicurio-registry.kafka.svc.cluster.local:8080/health/ready` |

### Port-Forward (local access)

```bash
kubectl -n kafka port-forward svc/apicurio-registry 8080:8080
# UI:  http://localhost:8080/ui
# API: http://localhost:8080/apis/registry/v3
```

## Schema Operations

### Register a schema

```bash
curl -X POST http://localhost:8080/apis/registry/v3/groups/default/artifacts \
  -H "Content-Type: application/json" \
  -H "X-Registry-ArtifactId: orders-value" \
  -d '{
    "artifactType": "AVRO",
    "firstVersion": {
      "version": "1",
      "content": {
        "content": "{\"type\":\"record\",\"name\":\"Order\",\"namespace\":\"com.example\",\"fields\":[{\"name\":\"order_id\",\"type\":\"string\"},{\"name\":\"customer_id\",\"type\":\"string\"},{\"name\":\"amount\",\"type\":\"double\"},{\"name\":\"order_time\",\"type\":{\"type\":\"long\",\"logicalType\":\"timestamp-millis\"}}]}",
        "contentType": "application/json"
      }
    }
  }'
```

### Retrieve a schema

```bash
curl http://localhost:8080/apis/registry/v3/groups/default/artifacts/orders-value/versions/1/content
```

### List all artifacts

```bash
curl http://localhost:8080/apis/registry/v3/search/artifacts
```

## Kafka Producer/Consumer Integration

### Java (with Apicurio SerDe)

```xml
<!-- pom.xml -->
<dependency>
    <groupId>io.apicurio</groupId>
    <artifactId>apicurio-registry-serdes-avro-serde</artifactId>
    <version>3.1.7</version>
</dependency>
```

```java
// Producer config
props.put("schema.registry.url", "http://apicurio-registry.kafka.svc.cluster.local:8080/apis/registry/v3");
props.put("key.serializer", "org.apache.kafka.common.serialization.StringSerializer");
props.put("value.serializer", "io.apicurio.registry.serde.avro.AvroKafkaSerializer");
props.put("apicurio.registry.auto-register", "true");
```

### Python (with confluent-kafka + Apicurio)

```python
from confluent_kafka.schema_registry import SchemaRegistryClient
from confluent_kafka.schema_registry.avro import AvroSerializer

# Apicurio is compatible with Confluent Schema Registry API (v7 compat mode)
schema_registry = SchemaRegistryClient({
    "url": "http://apicurio-registry.kafka.svc.cluster.local:8080/apis/ccompat/v7"
})
```

## File Structure

```
apicurio/
├── README.md
├── deployment/                         # Rendered output (.gitignored)
│   ├── .gitignore                      # Ignores *.yaml rendered files
│   └── rendered/
│       ├── templates/                  # Core resources (config-driven)
│       │   ├── apicurio-registry-deployment.yaml
│       │   └── apicurio-registry-service.yaml
│       └── custom/                     # Copied from manifests/ (reference)
│           └── apicurio-registry.yaml
├── manifests/
│   └── apicurio-registry.yaml         # Reference manifest (static, hardcoded values)
└── scripts/
    ├── build.sh                        # Deploy (config-driven, inline manifest)
    ├── destroy.sh                      # Teardown (preserves kafkasql-journal topic)
    ├── regenerate-rendered.sh          # Regenerate deployment/rendered/ from config.yaml
    └── test/
        └── test-apicurio.sh            # Test: pod status, health, schema CRUD
```
