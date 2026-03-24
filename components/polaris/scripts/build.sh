#!/bin/bash
set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}  Deploying Apache Polaris + PostgreSQL${NC}"
echo -e "${CYAN}============================================${NC}"

# 1. Create namespace
echo -e "\n${YELLOW}[1] Creating namespace 'polaris'...${NC}"
kubectl create namespace polaris --dry-run=client -o yaml | kubectl apply -f -

# 2. Deploy PostgreSQL Cluster
echo -e "\n${YELLOW}[2] Deploying PostgreSQL (CloudNativePG)...${NC}"
kubectl apply -f manifests/postgres.yaml

# 3. Wait for database readiness
echo -e "\n${YELLOW}[3] Waiting for database 'polaris-db' to be ready...${NC}"
echo -e "${CYAN}    (This may take a minute for the first pod to start)${NC}"
kubectl wait --for=jsonpath='{.status.phase}'=Ready cluster/polaris-db -n polaris --timeout=300s

# 4. Deploy Polaris via Helm
echo -e "\n${YELLOW}[4] Deploying Apache Polaris via Helm...${NC}"
helm dependency update helm/
helm upgrade --install polaris helm/ \
  --namespace polaris \
  --values helm/values.yaml

echo -e "\n${GREEN}============================================${NC}"
echo -e "${GREEN}  Apache Polaris deployment started!${NC}"
echo -e "${GREEN}============================================${NC}"
echo -e "Run ./scripts/access.sh to check status and get credentials."
