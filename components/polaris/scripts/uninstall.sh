#!/bin/bash

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${RED}============================================${NC}"
echo -e "${RED}  Uninstalling Apache Polaris${NC}"
echo -e "${RED}============================================${NC}"

# 1. Uninstall Helm release
echo -e "\n${YELLOW}[1] Uninstalling Polaris Helm chart...${NC}"
helm uninstall polaris --namespace polaris 2>/dev/null || echo "Polaris helm release not found."

# 2. Delete PostgreSQL Cluster
echo -e "\n${YELLOW}[2] Deleting PostgreSQL cluster 'polaris-db'...${NC}"
kubectl delete cluster polaris-db --namespace polaris 2>/dev/null || echo "Postgres cluster not found."

# 3. Delete Namespace (Optional/Confirmation)
echo -e "\n${CYAN}[3] Cleaning up namespace 'polaris'...${NC}"
kubectl delete namespace polaris 2>/dev/null || echo "Namespace polaris not found."

echo -e "\n${RED}============================================${NC}"
echo -e "${RED}  Apache Polaris uninstalled.${NC}"
echo -e "${RED}============================================${NC}"
