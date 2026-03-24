# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Kubernetes data infrastructure sandbox deploying 15+ components on minikube. Two deployment methods:
- **Hyper-V** (Windows + WSL) — recommended, uses block devices for Ceph
- **Vagrant + VirtualBox** — portable, works without Hyper-V

Core: Rook-Ceph S3 object store with pluggable databases (PostgreSQL, Milvus, Dremio), data processing (Spark, Airflow), event streaming (Strimzi Kafka, Knative), and ML (Ollama).

## Configuration

`config.yaml` is the single source of truth. It defines VM resources, minikube settings, and all component toggles (enabled/disabled, namespace, chart version, custom options).

`scripts/common/config-loader.sh` parses `config.yaml` via `yq` into 200+ shell variables. Every build/destroy script sources this loader. `scripts/common/utils.sh` provides shared utilities (WSL detection, path conversion, colored output, wait-for-pod logic).

## Build Commands

### Hyper-V Method (from Windows PowerShell, then WSL)
```powershell
.\scripts\minikube-hyperv\setup-hyperv.ps1    # Create Hyper-V VMs + extra disks
```
```bash
./scripts/minikube-hyperv/setup-kubeconfig.sh  # Configure kubectl in WSL
```

### Vagrant Method
```bash
./scripts/vagrant/vagrant.sh build    # Create VM, provision tools, start minikube
./scripts/vagrant/vagrant.sh start|stop|destroy|ssh|status|snapshot  # Lifecycle
```

### Minikube (inside VM or WSL)
```bash
./scripts/minikube/build.sh           # Start cluster, configure addons, tune nodes
./scripts/minikube/destroy.sh         # Delete cluster
./scripts/minikube/health-check.sh    # Status checks
```

### Components (each follows the same pattern)
```bash
./components/<name>/scripts/build.sh      # Deploy via Helm
./components/<name>/scripts/destroy.sh    # Uninstall
```
Ceph must be deployed first — other components depend on it for storage.

## Component Build Pattern

All component scripts follow this flow:
1. Source `config-loader.sh` to get variables from `config.yaml`
2. Check `enabled` flag in config
3. Verify kubectl access
4. Add Helm repo, create namespace
5. `helm upgrade --install` with chart version from config and `helm/values.yaml` overrides
6. Wait for pods ready

Some components use custom manifests (`deployment/` or `manifests/`) instead of or alongside Helm.

## Architecture

```
config.yaml                          # Central config (VM, minikube, all components)
scripts/
  common/config-loader.sh            # YAML→shell variable loader (sourced by everything)
  common/utils.sh                    # Shared bash utilities
  minikube-hyperv/                   # PowerShell + Bash for Hyper-V deployment
  minikube/                          # Minikube lifecycle (build, destroy, health)
  vagrant/                           # Vagrant VM lifecycle (vagrant.sh wrapper)
  provision/                         # VM bootstrap (Docker, minikube, kubectl, helm, yq)
components/
  ceph/                              # Rook-Ceph (operator + cluster, two-phase Helm install)
  monitoring/                        # Grafana, Prometheus, Loki
  databases/                         # CloudNativePG PostgreSQL, Milvus, Dremio
  events/                            # Strimzi Kafka, Apicurio, Knative, Envoy Gateway, Kafka UI, Camel K, Istio
  spark/                             # Apache and Kubeflow Spark operators
  de/                                # Data engineering (Gluten, Iceberg)
  airflow/                           # Apache Airflow
  ollama/                            # LLM serving
docs/
  architecture/                      # C4 model (Structurizr DSL → PlantUML → SVG)
```

## Ceph-Specific Notes

Ceph is the most complex component. Key files: `components/ceph/scripts/build.sh` (two-phase: operator then cluster), `destroy.sh` (10-step teardown with full disk wipe), `pre-stop.sh` / `post-start.sh` (graceful minikube lifecycle).

- Rook v1.19.1 with Ceph v20 (Tentacle)
- v1.19 moved `cephVersion` to top-level `cephImage` in Helm values
- Bluestore labels live at 1GB and 10GB offsets — wiping only the beginning of a disk is insufficient
- Hyper-V device names (`/dev/sdX`) are unstable across reboots — use `/dev/disk/by-path/` stable identifiers
- Minikube Hyper-V root filesystem is tmpfs; `dataDirHostPath` must point to the persistent mount at `/tmp/hostpath_pv/rook`

## Architecture Docs Generation

```bash
cd docs/architecture
./scripts/generate-diagrams.sh    # workspace.dsl → PlantUML → SVG → Markdown
```

Uses Structurizr C4 model. Hand-maintained extras in `extras/` are merged with generated content.

## Access Dashboards and Services

Each script sets up port-forwarding and prints credentials:
- `components/monitoring/scripts/access-grafana.sh` — Grafana (port 3000)
- `components/ceph/scripts/dashboard.sh` — Ceph dashboard (7000) + S3 gateway (7480)
- `components/dremio/scripts/dashboard.sh` — Dremio UI
- `components/airflow/scripts/access-webserver.sh` — Airflow webserver
- `scripts/minikube/access-dashboard.sh` — K8s dashboard (30080)

## Validate Base Infrastructure

```bash
components/ceph/scripts/test/test-s3.sh
components/ceph/scripts/test/test-block-storage.sh
components/ceph/scripts/test/test-filesystem.sh
```

## Multi-Repo Usage

This is a shared infrastructure repo. Multiple project repos depend on it for their K8s runtime. Project repos should:
- Reference this repo's `config.yaml` for namespaces, versions, and enabled components
- Source `scripts/common/config-loader.sh` to get infra variables in their own scripts
- Use `components/<name>/scripts/build.sh` to activate components they need

A CLAUDE.md template for new project repos is at `docs/project-claude-template.md`.

## Shell Script Conventions

- All bash scripts source `scripts/common/config-loader.sh` for configuration
- PowerShell scripts (Hyper-V) source `scripts/minikube-hyperv/common.ps1` for shared config
- Colored output via `utils.sh` functions (`info`, `warn`, `error`, `success`)
- Components check their `enabled` flag before proceeding
- Helm chart versions are always sourced from `config.yaml`, never hardcoded in scripts
