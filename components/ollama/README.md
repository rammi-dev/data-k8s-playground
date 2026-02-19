# Ollama

Local LLM inference server with OpenAI-compatible REST API. Runs models on CPU (no GPU required).

| Property | Value |
|----------|-------|
| Helm Chart | [otwld/ollama](https://github.com/otwld/ollama-helm) v1.43.0 |
| App Version | Ollama 0.9.0 |
| Default Model | tinyllama (~637 MB) |
| Storage | Ceph RBD (`ceph-block`), 20Gi |
| API Port | 11434 |

## Prerequisites

- Kubernetes cluster running
- Ceph block storage (`ceph-block` StorageClass) available
- Helm 3.x

## Deploy

```bash
./scripts/build.sh
```

## Remove

```bash
./scripts/destroy.sh
```

## Access

```bash
# Port-forward to local machine
kubectl port-forward svc/ollama -n ollama 11434:11434
```

## API Examples

```bash
# List models
curl http://localhost:11434/api/tags

# Generate text
curl http://localhost:11434/api/generate -d '{
  "model": "tinyllama",
  "prompt": "Explain Kubernetes in one sentence"
}'

# Chat
curl http://localhost:11434/api/chat -d '{
  "model": "tinyllama",
  "messages": [{"role": "user", "content": "Hello"}]
}'

# Generate embeddings (for Milvus/RAG pipelines)
curl http://localhost:11434/api/embed -d '{
  "model": "tinyllama",
  "input": "Some text to embed"
}'

# OpenAI-compatible endpoint
curl http://localhost:11434/v1/chat/completions -d '{
  "model": "tinyllama",
  "messages": [{"role": "user", "content": "Hello"}]
}'
```

## Pull Additional Models

```bash
# From inside the cluster
kubectl exec -n ollama deploy/ollama -- ollama pull nomic-embed-text
kubectl exec -n ollama deploy/ollama -- ollama pull llama3.2:1b

# Or via API
curl http://localhost:11434/api/pull -d '{"name": "nomic-embed-text"}'
```

## From Other Pods

Any pod in the cluster can call Ollama via its ClusterIP service:

```
http://ollama.ollama.svc:11434/api/generate
```

## Configuration

Edit `helm/values.yaml` to change:
- `ollama.models.pull` — models to download on startup
- `ollama.resources` — CPU/memory limits
- `ollama.persistence.size` — PVC size for model storage

Re-run `./scripts/build.sh` after changes.

## File Structure

```
components/ollama/
├── README.md
├── helm/
│   ├── Chart.yaml          # Wrapper chart (otwld/ollama dependency)
│   └── values.yaml         # Resource limits, persistence, model config
└── scripts/
    ├── build.sh             # Deploy
    └── destroy.sh           # Teardown
```
