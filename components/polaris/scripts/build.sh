#!/bin/bash
set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Get script directory for reliable relative paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POLARIS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Read version from Chart.yaml (single source of truth)
POLARIS_VERSION=$(grep 'appVersion:' "$POLARIS_DIR/helm/Chart.yaml" | sed 's/appVersion: *"\(.*\)"/\1/')

echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}  Deploying Apache Polaris ${POLARIS_VERSION}${NC}"
echo -e "${CYAN}============================================${NC}"

# 1. Create namespace
echo -e "\n${YELLOW}[1] Creating namespace 'polaris'...${NC}"
kubectl create namespace polaris --dry-run=client -o yaml | kubectl apply -f -

# 2. Deploy PostgreSQL Cluster (idempotent)
echo -e "\n${YELLOW}[2] Deploying PostgreSQL (CloudNativePG)...${NC}"
kubectl apply -f "$POLARIS_DIR/manifests/postgres.yaml"

# 3. Wait for database readiness
echo -e "\n${YELLOW}[3] Waiting for database 'polaris-db' to be ready...${NC}"
echo -e "${CYAN}    (Checking for ready instances...)${NC}"
kubectl wait --for=jsonpath='{.status.readyInstances}'=1 cluster/polaris-db -n polaris --timeout=300s

# 4. Create JDBC credentials secret for Polaris
echo -e "\n${YELLOW}[4] Creating JDBC credentials secret...${NC}"
PG_USER=$(kubectl get secret polaris-db-app -n polaris -o jsonpath='{.data.username}' | base64 -d)
PG_PASS=$(kubectl get secret polaris-db-app -n polaris -o jsonpath='{.data.password}' | base64 -d)
PG_JDBC_URL="jdbc:postgresql://polaris-db-rw.polaris.svc.cluster.local:5432/polaris"

kubectl create secret generic polaris-jdbc-credentials \
  --namespace polaris \
  --from-literal=jdbcUrl="$PG_JDBC_URL" \
  --from-literal=username="$PG_USER" \
  --from-literal=password="$PG_PASS" \
  --dry-run=client -o yaml | kubectl apply -f -

echo -e "${GREEN}    JDBC secret created/updated.${NC}"

# 5. Add Helm repo and update dependencies
echo -e "\n${YELLOW}[5] Updating Helm dependencies...${NC}"
helm repo add polaris https://downloads.apache.org/incubator/polaris/helm-chart 2>/dev/null || true
helm repo update polaris
helm dependency update "$POLARIS_DIR/helm/"

# 6. Deploy Polaris via Helm
echo -e "\n${YELLOW}[6] Deploying Apache Polaris via Helm...${NC}"
helm upgrade --install polaris "$POLARIS_DIR/helm/" \
  --namespace polaris \
  --values "$POLARIS_DIR/helm/values.yaml" \
  --devel

# 7. Wait for Polaris to be ready (init container bootstraps DB, then server starts)
echo -e "\n${YELLOW}[7] Waiting for Polaris to be ready...${NC}"
kubectl rollout status deployment/polaris -n polaris --timeout=180s

# 8. Extract bootstrap credentials from init container logs
echo -e "\n${YELLOW}[8] Bootstrap credentials...${NC}"
POD_NAME=$(kubectl get pods -n polaris -l app.kubernetes.io/name=polaris -o jsonpath='{.items[0].metadata.name}')
CREDS=$(kubectl logs "$POD_NAME" -c bootstrap 2>/dev/null | grep "successfully bootstrapped" || true)
if [ ! -z "$CREDS" ]; then
    echo -e "${GREEN}    $CREDS${NC}"
    echo -e "${CYAN}    Credentials: root / s3cr3t (set via -c flag in values.yaml)${NC}"
else
    echo -e "${CYAN}    Check: kubectl -n polaris logs \$(kubectl get pods -n polaris -l app.kubernetes.io/name=polaris -o jsonpath='{.items[0].metadata.name}') -c bootstrap${NC}"
fi

echo -e "\n${GREEN}============================================${NC}"
echo -e "${GREEN}  Apache Polaris deployed and bootstrapped!${NC}"
echo -e "${GREEN}============================================${NC}"
echo -e "Run ./scripts/access.sh to check status and get credentials."
