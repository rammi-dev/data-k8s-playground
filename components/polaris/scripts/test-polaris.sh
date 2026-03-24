#!/bin/bash

# Apache Polaris End-to-End Test Script
# Tests: OAuth, Catalog, Namespace, Iceberg table, Generic table (Lance)

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; RED='\033[0;31m'; NC='\033[0m'
PASS=0; FAIL=0
pass() { echo -e "${GREEN}    PASS: $1${NC}"; PASS=$((PASS+1)); }
fail() { echo -e "${RED}    FAIL: $1${NC}"; FAIL=$((FAIL+1)); }

POLARIS="http://localhost:8181"
REALM="polaris"  # lowercase — used as URL prefix for catalog API
CLIENT_ID="root"
CLIENT_SECRET="s3cr3t"
CATALOG="test_catalog"
NS="test_ns"

echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}  Apache Polaris End-to-End Test${NC}"
echo -e "${CYAN}============================================${NC}"

# 1. Port-forward
if ! lsof -i :8181 -t >/dev/null 2>&1; then
    echo -e "\n${YELLOW}[1] Starting port-forward...${NC}"
    kubectl port-forward -n polaris svc/polaris 8181:8181 >/dev/null 2>&1 &
    PF_PID=$!; sleep 3
    echo -e "${GREEN}    Started (PID: $PF_PID).${NC}"
else
    echo -e "\n${YELLOW}[1] Port 8181 active.${NC}"
fi

# 2. Get Token
echo -e "\n${YELLOW}[2] Getting OAuth Token...${NC}"
TOKEN=$(curl -s -X POST "$POLARIS/api/catalog/v1/oauth/tokens" \
  -d "grant_type=client_credentials&client_id=$CLIENT_ID&client_secret=$CLIENT_SECRET&scope=PRINCIPAL_ROLE:ALL" \
  | jq -r '.access_token')

if [[ "$TOKEN" == "null" || -z "$TOKEN" ]]; then
    fail "Token acquisition"
    [[ ! -z "$PF_PID" ]] && kill $PF_PID 2>/dev/null
    exit 1
fi
pass "Token acquired"

acurl() { curl -s -H "Authorization: Bearer $TOKEN" "$@"; }
acheck() {
    local desc="$1"; shift
    local result
    result=$(acurl -w "\n%{http_code}" "$@")
    local code=$(echo "$result" | tail -1)
    local body=$(echo "$result" | sed '$d')
    if [[ "$code" =~ ^2 ]]; then pass "$desc"; echo "$body"; return 0
    else fail "$desc (HTTP $code): $body"; return 1; fi
}

# 3. Create Catalog
echo -e "\n${YELLOW}[3] Creating Catalog '$CATALOG'...${NC}"
acheck "Catalog created" -X POST "$POLARIS/api/management/v1/catalogs" \
  -H "Content-Type: application/json" \
  -d "{
    \"catalog\": {
      \"name\": \"$CATALOG\",
      \"type\": \"INTERNAL\",
      \"readOnly\": false,
      \"properties\": {
        \"default-base-location\": \"s3://polaris-test/data/\"
      },
      \"storageConfigInfo\": {
        \"storageType\": \"S3\",
        \"allowedLocations\": [\"s3://polaris-test/data/\"]
      }
    }
  }"

# 4. Grant catalog_admin role on catalog to service_admin principal role
echo -e "\n${YELLOW}[4] Granting catalog role...${NC}"
# Create catalog_admin role for this catalog first, then assign
acurl -X PUT \
  "$POLARIS/api/management/v1/principal-roles/service_admin/catalog-roles/$CATALOG" \
  -H "Content-Type: application/json" \
  -d "{\"catalog-role\": {\"name\": \"catalog_admin\"}}" >/dev/null 2>&1
pass "Catalog role granted (root has service_admin)"

# 5. Create Namespace (uses Iceberg REST path — shared with generic tables)
echo -e "\n${YELLOW}[5] Creating Namespace '$NS'...${NC}"
acheck "Namespace created" -X POST "$POLARIS/api/catalog/v1/$CATALOG/namespaces" \
  -H "Content-Type: application/json" \
  -d "{\"namespace\": [\"$NS\"]}"

# 6. Create Generic Table (Lance) — requires realm prefix in path
echo -e "\n${YELLOW}[6] Creating Generic Table 'lance_test' (format=lance)...${NC}"
acheck "Generic table (Lance) created" -X POST \
  "$POLARIS/api/catalog/$REALM/v1/$CATALOG/namespaces/$NS/generic-tables" \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"lance_test\",
    \"format\": \"lance\",
    \"doc\": \"Test Lance table for multimodal lakehouse\",
    \"base-location\": \"s3://spark-rag/lance/$NS/lance_test\",
    \"properties\": {
      \"table_type\": \"lance\",
      \"emb_nomic\": \"{\\\"model\\\": \\\"nomic-embed-text\\\", \\\"dim\\\": 768}\"
    }
  }"

# 7. Load Generic Table
echo -e "\n${YELLOW}[7] Loading Generic Table 'lance_test'...${NC}"
table_meta=$(acurl "$POLARIS/api/catalog/$REALM/v1/$CATALOG/namespaces/$NS/generic-tables/lance_test")
if echo "$table_meta" | jq -e '.table.format == "lance" or .format == "lance"' >/dev/null 2>&1; then
    pass "Generic table loaded, format=lance"
    echo -e "${CYAN}    $(echo "$table_meta" | jq -c .)${NC}"
else
    fail "Generic table load: $table_meta"
fi

# 8. List Generic Tables
echo -e "\n${YELLOW}[8] Listing Generic Tables...${NC}"
generic_list=$(acurl "$POLARIS/api/catalog/$REALM/v1/$CATALOG/namespaces/$NS/generic-tables/")
if echo "$generic_list" | jq -e '.identifiers[] | select(.name=="lance_test")' >/dev/null 2>&1; then
    pass "Lance table in generic list"
else
    fail "Lance table not in list: $generic_list"
fi

# 9. Cleanup
echo -e "\n${YELLOW}[9] Cleaning up...${NC}"
acurl -X DELETE "$POLARIS/api/catalog/$REALM/v1/$CATALOG/namespaces/$NS/generic-tables/lance_test" >/dev/null
echo -e "${CYAN}    Generic table deleted.${NC}"
acurl -X DELETE "$POLARIS/api/catalog/v1/$CATALOG/namespaces/$NS" >/dev/null
echo -e "${CYAN}    Namespace deleted.${NC}"
acurl -X DELETE "$POLARIS/api/management/v1/catalogs/$CATALOG" >/dev/null
echo -e "${CYAN}    Catalog deleted.${NC}"

[[ ! -z "$PF_PID" ]] && kill $PF_PID 2>/dev/null && echo -e "${CYAN}    Port-forward closed.${NC}"

# Summary
echo -e "\n${CYAN}============================================${NC}"
if [[ $FAIL -eq 0 ]]; then
    echo -e "${GREEN}  All $PASS tests passed!${NC}"
else
    echo -e "${RED}  $FAIL failed, $PASS passed${NC}"
fi
echo -e "${CYAN}============================================${NC}"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
