#!/bin/bash

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

# Credentials — must match values.yaml bootstrap -c flag
CLIENT_ID="root"
CLIENT_SECRET="s3cr3t"
POLARIS="http://localhost:8181"

echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}  Apache Polaris Access Information${NC}"
echo -e "${CYAN}============================================${NC}"

# 1. Pod status
echo -e "\n${YELLOW}[1] Pod Status:${NC}"
kubectl get pods -n polaris -l app.kubernetes.io/name=polaris 2>/dev/null || echo -e "${RED}    No pods found.${NC}"

# 2. Bootstrap status
echo -e "\n${YELLOW}[2] Bootstrap Status:${NC}"
POD_NAME=$(kubectl get pods -n polaris -l app.kubernetes.io/name=polaris -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ ! -z "$POD_NAME" ]; then
    BOOTSTRAP_LOG=$(kubectl logs -n polaris "$POD_NAME" -c bootstrap 2>/dev/null | tail -3)
    if echo "$BOOTSTRAP_LOG" | grep -q "successfully bootstrapped"; then
        echo -e "${GREEN}    Bootstrapped.${NC}"
    else
        echo -e "${RED}    Not bootstrapped or init container not run yet.${NC}"
    fi
    echo -e "${CYAN}    $BOOTSTRAP_LOG${NC}"
else
    echo -e "${RED}    No Polaris pod found.${NC}"
fi

# 3. Credentials
echo -e "\n${YELLOW}[3] Credentials:${NC}"
echo -e "    Client ID:     ${GREEN}$CLIENT_ID${NC}"
echo -e "    Client Secret:  ${GREEN}$CLIENT_SECRET${NC}"

# 4. Port-forward + token
echo -e "\n${YELLOW}[4] Port-Forward & Token:${NC}"
if ! lsof -i :8181 -t >/dev/null 2>&1; then
    echo -e "${CYAN}    Starting port-forward...${NC}"
    kubectl port-forward -n polaris svc/polaris 8181:8181 >/dev/null 2>&1 &
    PF_PID=$!
    sleep 3
    echo -e "${GREEN}    Port-forward started (PID: $PF_PID).${NC}"
else
    echo -e "${CYAN}    Port 8181 already active.${NC}"
fi

TOKEN=$(curl -s -X POST "$POLARIS/api/catalog/v1/oauth/tokens" \
  -d "grant_type=client_credentials&client_id=$CLIENT_ID&client_secret=$CLIENT_SECRET&scope=PRINCIPAL_ROLE:ALL" \
  | jq -r '.access_token' 2>/dev/null)

if [[ "$TOKEN" != "null" && ! -z "$TOKEN" ]]; then
    echo -e "${GREEN}    Token acquired.${NC}"
    echo -e "\n${YELLOW}[5] API Examples:${NC}"
    echo -e "${CYAN}    # Get token${NC}"
    echo -e "    curl -s -X POST $POLARIS/api/catalog/v1/oauth/tokens \\"
    echo -e "      -d 'grant_type=client_credentials&client_id=$CLIENT_ID&client_secret=$CLIENT_SECRET&scope=PRINCIPAL_ROLE:ALL'"
    echo -e ""
    echo -e "${CYAN}    # List catalogs${NC}"
    echo -e "    curl -s $POLARIS/api/management/v1/catalogs -H 'Authorization: Bearer \$TOKEN'"
    echo -e ""
    echo -e "${CYAN}    # Create Lance generic table (realm prefix required)${NC}"
    echo -e "    curl -s -X POST $POLARIS/api/catalog/polaris/v1/\$CATALOG/namespaces/\$NS/generic-tables \\"
    echo -e "      -H 'Authorization: Bearer \$TOKEN' -H 'Content-Type: application/json' \\"
    echo -e "      -d '{\"name\":\"my_table\",\"format\":\"lance\",\"base-location\":\"s3://bucket/path\"}'"
else
    echo -e "${RED}    Failed to get token. Is Polaris running?${NC}"
fi

# 6. Postgres
echo -e "\n${YELLOW}[6] Metadata Database (PostgreSQL):${NC}"
PG_PASS=$(kubectl get secret polaris-db-app -n polaris -o jsonpath='{.data.password}' 2>/dev/null | base64 -d)
echo -e "    Host:     polaris-db-rw.polaris.svc.cluster.local:5432"
echo -e "    Database: polaris"
echo -e "    User:     polaris"
echo -e "    Password: $PG_PASS"

# 7. Key API paths
echo -e "\n${YELLOW}[7] API Path Reference:${NC}"
echo -e "    OAuth:           /api/catalog/v1/oauth/tokens"
echo -e "    Management:      /api/management/v1/catalogs"
echo -e "    Namespaces:      /api/catalog/v1/{catalog}/namespaces"
echo -e "    Generic Tables:  /api/catalog/polaris/v1/{catalog}/namespaces/{ns}/generic-tables"
echo -e "    ${CYAN}Note: Generic table API requires realm prefix 'polaris' in the URL${NC}"

echo -e "\n${CYAN}============================================${NC}"
