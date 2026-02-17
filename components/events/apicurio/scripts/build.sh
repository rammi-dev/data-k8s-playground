#!/bin/bash
# Deploy Apicurio Registry (Schema Registry) to the Kubernetes cluster
# Requires: Strimzi Kafka deployed (for KafkaSQL storage backend)
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
COMPONENT_DIR="$PROJECT_ROOT/components/events/apicurio"

source "$PROJECT_ROOT/scripts/common/utils.sh"
source "$PROJECT_ROOT/scripts/common/config-loader.sh"

# Check if component is enabled
if [[ "$APICURIO_ENABLED" != "true" ]]; then
    print_error "Apicurio Registry is not enabled in config.yaml"
    print_info "Set 'components.apicurio.enabled: true' in config.yaml"
    exit 1
fi

# Check if Kubernetes cluster is accessible
if ! kubectl cluster-info &>/dev/null; then
    print_error "Kubernetes cluster is not accessible"
    exit 1
fi

print_info "Deploying Apicurio Registry v${APICURIO_VERSION} (storage: ${APICURIO_STORAGE})"
print_info "Namespace: $APICURIO_NAMESPACE"
echo "=========================================="

# ============================================================================
# PRE-FLIGHT: Verify Kafka is running (required for kafkasql storage)
# ============================================================================
if [[ "$APICURIO_STORAGE" == "kafkasql" ]]; then
    print_info "Verifying Kafka cluster is available..."
    if ! kubectl get kafka "$STRIMZI_KAFKA_CLUSTER_NAME" -n "$STRIMZI_NAMESPACE" \
        -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q "True"; then
        print_error "Kafka cluster '${STRIMZI_KAFKA_CLUSTER_NAME}' is not ready in namespace '${STRIMZI_NAMESPACE}'"
        print_info "Deploy Strimzi first: ./components/events/strimzi/scripts/build.sh"
        exit 1
    fi
    print_success "  Kafka cluster ready"
fi

# ============================================================================
# STEP 1: Ensure namespace exists
# ============================================================================
print_info "Step 1: Ensuring namespace exists..."
kubectl create namespace "$APICURIO_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
print_success "  Namespace $APICURIO_NAMESPACE ready"

# ============================================================================
# STEP 2: Deploy Apicurio Registry (config-driven manifest)
# ============================================================================
print_info "Step 2: Deploying Apicurio Registry..."

BOOTSTRAP="${STRIMZI_KAFKA_CLUSTER_NAME}-kafka-bootstrap.${STRIMZI_NAMESPACE}.svc.cluster.local:9092"

# Build env vars block — kafkasql needs bootstrap servers, mem does not
ENV_VARS="            - name: APICURIO_STORAGE_KIND
              value: \"${APICURIO_STORAGE}\""

if [[ "$APICURIO_STORAGE" == "kafkasql" ]]; then
    ENV_VARS="${ENV_VARS}
            - name: APICURIO_KAFKASQL_BOOTSTRAP_SERVERS
              value: \"${BOOTSTRAP}\""
fi

kubectl apply -n "$APICURIO_NAMESPACE" -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: apicurio-registry
  labels:
    app: apicurio-registry
spec:
  replicas: ${APICURIO_REPLICAS}
  selector:
    matchLabels:
      app: apicurio-registry
  template:
    metadata:
      labels:
        app: apicurio-registry
    spec:
      containers:
        - name: apicurio-registry
          image: ${APICURIO_IMAGE}:${APICURIO_VERSION}
          ports:
            - name: http
              containerPort: 8080
              protocol: TCP
          env:
${ENV_VARS}
          resources:
            requests:
              cpu: 200m
              memory: 512Mi
            limits:
              cpu: 1000m
              memory: 1Gi
          readinessProbe:
            httpGet:
              path: /health/ready
              port: 8080
            initialDelaySeconds: 15
            periodSeconds: 10
            timeoutSeconds: 5
          livenessProbe:
            httpGet:
              path: /health/live
              port: 8080
            initialDelaySeconds: 30
            periodSeconds: 10
            timeoutSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: apicurio-registry
  labels:
    app: apicurio-registry
spec:
  type: ClusterIP
  ports:
    - name: http
      port: 8080
      targetPort: 8080
      protocol: TCP
  selector:
    app: apicurio-registry
EOF

print_success "  Manifests applied"

# ============================================================================
# STEP 3: Wait for Apicurio to be ready
# ============================================================================
print_info "Step 3: Waiting for Apicurio Registry to be ready..."
kubectl rollout status deployment/apicurio-registry -n "$APICURIO_NAMESPACE" --timeout=120s

print_success "  Apicurio Registry ready"

# ============================================================================
# STATUS
# ============================================================================
print_success "Apicurio Registry Deployed!"
echo "=========================================="
echo ""
print_info "Apicurio Pods:"
kubectl -n "$APICURIO_NAMESPACE" get pods -l app=apicurio-registry
echo ""
print_info "API:  http://apicurio-registry.${APICURIO_NAMESPACE}.svc.cluster.local:8080/apis/registry/v3"
print_info "UI:   http://apicurio-registry.${APICURIO_NAMESPACE}.svc.cluster.local:8080/ui"
echo ""
print_info "Next steps:"
print_info "  1. Port-forward UI:  kubectl -n $APICURIO_NAMESPACE port-forward svc/apicurio-registry 8080:8080"
print_info "  2. Register schema:  curl -X POST http://localhost:8080/apis/registry/v3/groups/default/artifacts \\"
print_info "                         -H 'Content-Type: application/json' -d '{...}'"
