# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

<!-- Describe what this app/pipeline does -->

## Infrastructure Dependencies

This project runs on the K8s cluster managed by the infrastructure repo at `/mnt/c/Work/playground`.

### Required components
<!-- List which infra components this project needs (beyond the always-on base of K8s + monitoring + Ceph) -->
<!-- Example: -->
<!-- - Kafka (`kafka` ns) — event streaming for ingestion pipeline -->
<!-- - Milvus (`milvus` ns) — vector store for embeddings -->

To activate missing components, see the user-level CLAUDE.md or run:
```bash
/mnt/c/Work/playground/components/<name>/scripts/build.sh
```

## Build and Run

<!-- How to build, test, and run this specific project -->

## Project Structure

<!-- Key directories and files specific to this project -->
