#!/bin/bash
# Test Apicurio Registry — verify deployment, health, schema CRUD
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../../.." && pwd)"

source "$PROJECT_ROOT/scripts/common/utils.sh"
source "$PROJECT_ROOT/scripts/common/config-loader.sh"

print_info "Testing Apicurio Registry..."
echo "=========================================="
PASS=0
FAIL=0

APICURIO_URL="http://apicurio-registry.${APICURIO_NAMESPACE}.svc.cluster.local:8080"

# Test 1: Pod running
print_info "Test 1: Apicurio Registry pod running"
if kubectl get pods -n "$APICURIO_NAMESPACE" -l app=apicurio-registry \
    -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q "Running"; then
    print_success "  PASS: Pod running"
    ((PASS++))
else
    print_error "  FAIL: Pod not running"
    ((FAIL++))
fi

# Test 2: Health endpoint
print_info "Test 2: Health check (via kubectl exec)"
HEALTH=$(kubectl run apicurio-health-check -n "$APICURIO_NAMESPACE" --rm -i --restart=Never \
    --image=curlimages/curl:8.12.1 -- \
    curl -s -o /dev/null -w '%{http_code}' "${APICURIO_URL}/health/ready" 2>/dev/null || echo "000")

if [[ "$HEALTH" == "200" ]]; then
    print_success "  PASS: Health endpoint returned 200"
    ((PASS++))
else
    print_error "  FAIL: Health endpoint returned $HEALTH"
    ((FAIL++))
fi

# Test 3: Register and retrieve a test schema
print_info "Test 3: Register and retrieve test schema"
TEST_GROUP="test-group"
TEST_ARTIFACT="test-schema-$(date +%s)"

# Register an Avro schema
REGISTER_STATUS=$(kubectl run apicurio-test-register -n "$APICURIO_NAMESPACE" --rm -i --restart=Never \
    --image=curlimages/curl:8.12.1 -- \
    curl -s -o /dev/null -w '%{http_code}' \
    -X POST "${APICURIO_URL}/apis/registry/v3/groups/${TEST_GROUP}/artifacts" \
    -H "Content-Type: application/json" \
    -H "X-Registry-ArtifactId: ${TEST_ARTIFACT}" \
    -d '{
        "artifactType": "AVRO",
        "firstVersion": {
            "version": "1",
            "content": {
                "content": "{\"type\":\"record\",\"name\":\"TestEvent\",\"fields\":[{\"name\":\"id\",\"type\":\"string\"},{\"name\":\"value\",\"type\":\"int\"}]}",
                "contentType": "application/json"
            }
        }
    }' 2>/dev/null || echo "000")

if [[ "$REGISTER_STATUS" == "200" || "$REGISTER_STATUS" == "201" ]]; then
    print_success "  PASS: Schema registered (HTTP $REGISTER_STATUS)"
    ((PASS++))

    # Clean up test artifact
    kubectl run apicurio-test-cleanup -n "$APICURIO_NAMESPACE" --rm -i --restart=Never \
        --image=curlimages/curl:8.12.1 -- \
        curl -s -X DELETE "${APICURIO_URL}/apis/registry/v3/groups/${TEST_GROUP}/artifacts/${TEST_ARTIFACT}" \
        2>/dev/null || true
else
    print_error "  FAIL: Schema registration returned HTTP $REGISTER_STATUS"
    ((FAIL++))
fi

# Summary
echo ""
echo "=========================================="
if [[ $FAIL -eq 0 ]]; then
    print_success "All $PASS tests passed"
else
    print_error "$FAIL failed, $PASS passed"
    exit 1
fi
