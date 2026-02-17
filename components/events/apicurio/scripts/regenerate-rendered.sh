#!/bin/bash
# Regenerate rendered manifests for inspection
# Output: deployment/rendered/ (gitignored)
#
# Substitutes config.yaml values into the manifest template so you can
# inspect the exact YAML that build.sh would apply to the cluster.
#
# Layout mirrors Strimzi:
#   rendered/
#   ├── templates/         # Core resources (Deployment, Service)
#   └── custom/            # Post-deploy CRs (copied from manifests/)
#
# Usage: regenerate-rendered.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPONENT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_ROOT="$(cd "$COMPONENT_DIR/../../.." && pwd)"
RENDERED_DIR="$COMPONENT_DIR/deployment/rendered"

source "$PROJECT_ROOT/scripts/common/config-loader.sh"

BOOTSTRAP="${STRIMZI_KAFKA_CLUSTER_NAME}-kafka-bootstrap.${STRIMZI_NAMESPACE}.svc.cluster.local:9092"

echo "Regenerating Apicurio Registry rendered manifests"
echo "Image:     ${APICURIO_IMAGE}:${APICURIO_VERSION}"
echo "Storage:   ${APICURIO_STORAGE}"
echo "Namespace: ${APICURIO_NAMESPACE}"
echo "Replicas:  ${APICURIO_REPLICAS}"
echo "Bootstrap: ${BOOTSTRAP}"
echo "Output:    ${RENDERED_DIR}/"
echo ""

# ============================================================================
# STEP 1: Clean old rendered content
# ============================================================================
rm -rf "$RENDERED_DIR"
mkdir -p "$RENDERED_DIR/templates"
mkdir -p "$RENDERED_DIR/custom"

# ============================================================================
# STEP 2: Render config-driven templates (Deployment + Service)
# ============================================================================
echo "Rendering templates..."

# Build env vars — kafkasql needs bootstrap servers, mem does not
ENV_VARS="            - name: APICURIO_STORAGE_KIND
              value: \"${APICURIO_STORAGE}\""

if [[ "$APICURIO_STORAGE" == "kafkasql" ]]; then
    ENV_VARS="${ENV_VARS}
            - name: APICURIO_KAFKASQL_BOOTSTRAP_SERVERS
              value: \"${BOOTSTRAP}\""
fi

cat > "$RENDERED_DIR/templates/apicurio-registry-deployment.yaml" <<EOF
# Rendered by regenerate-rendered.sh — DO NOT EDIT
# Source: config.yaml → components.apicurio.*
---
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
EOF

cat > "$RENDERED_DIR/templates/apicurio-registry-service.yaml" <<EOF
# Rendered by regenerate-rendered.sh — DO NOT EDIT
# Source: config.yaml → components.apicurio.*
#
# API:  http://apicurio-registry.${APICURIO_NAMESPACE}.svc.cluster.local:8080/apis/registry/v3
# UI:   http://apicurio-registry.${APICURIO_NAMESPACE}.svc.cluster.local:8080/ui
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

echo "  templates/apicurio-registry-deployment.yaml"
echo "  templates/apicurio-registry-service.yaml"

# ============================================================================
# STEP 3: Copy custom manifests (post-deploy CRs from manifests/)
# ============================================================================
MANIFESTS_SRC="$COMPONENT_DIR/manifests"

if [[ -d "$MANIFESTS_SRC" ]]; then
    echo ""
    echo "Copying custom manifests..."
    cp -r "$MANIFESTS_SRC"/* "$RENDERED_DIR/custom/"
    for f in "$RENDERED_DIR/custom"/*.yaml; do
        echo "  custom/$(basename "$f")"
    done
fi

# ============================================================================
# STEP 4: Report results
# ============================================================================
TOTAL=$(find "$RENDERED_DIR" -name '*.yaml' -type f | wc -l)
echo ""
echo "Rendered $TOTAL file(s) to $RENDERED_DIR/"
echo ""
echo "To apply rendered manifests manually:"
echo "  kubectl apply -n ${APICURIO_NAMESPACE} -f ${RENDERED_DIR}/templates/"
echo "  kubectl apply -n ${APICURIO_NAMESPACE} -f ${RENDERED_DIR}/custom/"
