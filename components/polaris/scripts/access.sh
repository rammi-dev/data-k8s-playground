#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}  Apache Polaris Access Information${NC}"
echo -e "${CYAN}============================================${NC}"

# 1. Check pod status
echo -e "\n${YELLOW}[1] Pod Status:${NC}"
kubectl get pods -n polaris -l app.kubernetes.io/name=polaris

# 2. Get credentials
echo -e "\n${YELLOW}[2] Credentials:${NC}"
echo -e "${CYAN}    Note: Polaris management credentials are generated during bootstrap.${NC}"

# Try to find credentials from the bootstrap init-container logs if enabled,
# or from the main pod logs if bootstrap ran there.
POD_NAME=$(kubectl get pods -n polaris -l app.kubernetes.io/name=polaris -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ ! -z "$POD_NAME" ]; then
    echo -e "${CYAN}    Checking logs for bootstrap credentials...${NC}"
    # Polaris bootstrap usually prints clientID and clientSecret to stdout
    CREDENTIALS=$(kubectl logs -n polaris $POD_NAME | grep -E "principalId|clientSecret" | tail -n 2)
    if [ ! -z "$CREDENTIALS" ]; then
        echo -e "$CREDENTIALS"
    else
        echo -e "${RED}    Credentials not found in logs yet. The pod might still be starting.${NC}"
    fi
fi

# 3. Access instructions
echo -e "\n${YELLOW}[3] Access (Port-Forwarding):${NC}"
echo -e "Run this command in a separate terminal to access Polaris locally:"
echo -e "${GREEN}kubectl port-forward -n polaris svc/polaris 8181:8181${NC}"
echo -e "\nThen you can test the API:"
echo -e "${CYAN}curl -X GET http://localhost:8181/api/v1/realms/default-realm/principals -H \"Accept: application/json\"${NC}"

# 4. Postgres Connection (for inspection)
echo -e "\n${YELLOW}[4] Metadata Database (Postgres):${NC}"
PASSWORD=$(kubectl get secret polaris-db-app -n polaris -o jsonpath='{.data.password}' | base64 -d)
echo -e "Hostname: polaris-db-rw.polaris.svc.cluster.local"
echo -e "Database: polaris"
echo -e "User: polaris"
echo -e "Password: $PASSWORD"

echo -e "\n${CYAN}============================================${NC}"
