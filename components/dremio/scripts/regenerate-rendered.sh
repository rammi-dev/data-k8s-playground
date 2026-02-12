#!/bin/bash
# Regenerate rendered Helm templates for a specific environment
# Output: deployment/<env>/ (gitignored)
#
# Usage: regenerate-rendered.sh <lab|dev|prod> [--clean]
#   lab       Minimal single-node (POC/playground)
#   dev       Moderate multi-node (development)
#   prod      Full HA (production-like)
#   --clean   Delete empty template files after rendering
#
# Requires: helm/.env with credentials (see helm/.env.example)
set -e

ENV="${1:-}"
CLEAN_EMPTY=false
[[ "${2:-}" == "--clean" ]] && CLEAN_EMPTY=true

if [[ -z "$ENV" ]] || [[ ! "$ENV" =~ ^(lab|dev|prod)$ ]]; then
    echo "Usage: $0 <lab|dev|prod> [--clean]"
    echo ""
    echo "Environments:"
    echo "  lab   - Minimal single-node (POC/playground)"
    echo "  dev   - Moderate multi-node (development)"
    echo "  prod  - Full HA (production-like)"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPONENT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HELM_DIR="$COMPONENT_DIR/helm"
CHART_DIR="$HELM_DIR/dremio"
RENDERED_DIR="$COMPONENT_DIR/deployment/$ENV"
CUSTOM_DIR="$RENDERED_DIR/custom"

VALUES_BASE="$CHART_DIR/values.yaml"
VALUES_ENV="$HELM_DIR/values-${ENV}.yaml"
ENV_FILE="$HELM_DIR/.env"

# Validate files exist
for f in "$VALUES_BASE" "$VALUES_ENV"; do
    if [[ ! -f "$f" ]]; then
        echo "Error: Not found: $f"
        exit 1
    fi
done

# Load .env for credentials
if [[ -f "$ENV_FILE" ]]; then
    set -a
    source "$ENV_FILE"
    set +a
    echo "Loaded credentials from $ENV_FILE"
else
    echo "Warning: $ENV_FILE not found — using placeholder credentials"
    echo "  Copy .env.example to .env and fill in your credentials"
    DREMIO_REGISTRY_USER="PLACEHOLDER"
    DREMIO_REGISTRY_PASSWORD="PLACEHOLDER"
    DREMIO_REGISTRY_EMAIL="no-reply@dremio.local"
    DREMIO_REGISTRY="quay.io"
    DIST_ACCESS_KEY="PLACEHOLDER"
    DIST_SECRET_KEY="PLACEHOLDER"
    CATALOG_ACCESS_KEY="PLACEHOLDER"
    CATALOG_SECRET_KEY="PLACEHOLDER"
    DREMIO_MONGODB_PASSWORD="PLACEHOLDER"
    DREMIO_MONGODB_ADMIN_PASSWORD="PLACEHOLDER"
    DREMIO_MONGODB_MONITOR_PASSWORD="PLACEHOLDER"
    DREMIO_MONGODB_BACKUP_PASSWORD="PLACEHOLDER"
    DREMIO_MONGODB_USERADMIN_PASSWORD="PLACEHOLDER"
fi

echo "Environment: $ENV"
echo "Base values:  $VALUES_BASE"
echo "Env override: $VALUES_ENV"
echo "Output:       $RENDERED_DIR/"
echo ""

# ============================================================================
# STEP 1: Clean old rendered content
# ============================================================================
find "$RENDERED_DIR" -name '*.yaml' -type f -delete 2>/dev/null || true
find "$RENDERED_DIR" -mindepth 1 -type d -empty -delete 2>/dev/null || true
mkdir -p "$RENDERED_DIR" "$CUSTOM_DIR"

# ============================================================================
# STEP 2: Generate secrets from .env into custom/ folder
# ============================================================================
echo "Generating secrets in $CUSTOM_DIR/ ..."

# Image pull secret
DOCKER_CONFIG=$(echo -n "{\"auths\":{\"${DREMIO_REGISTRY:-quay.io}\":{\"username\":\"$DREMIO_REGISTRY_USER\",\"password\":\"$DREMIO_REGISTRY_PASSWORD\",\"email\":\"${DREMIO_REGISTRY_EMAIL:-no-reply@dremio.local}\"}}}" | base64 -w0)

cat > "$CUSTOM_DIR/image-pull-secret.yaml" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: dremio-quay-secret
  namespace: dremio
type: kubernetes.io/dockerconfigjson
data:
  .dockerconfigjson: ${DOCKER_CONFIG}
EOF

# Catalog S3 storage credentials
cat > "$CUSTOM_DIR/catalog-s3-secret.yaml" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: catalog-server-s3-storage-creds
  namespace: dremio
type: Opaque
stringData:
  awsAccessKeyId: "${CATALOG_ACCESS_KEY:-PLACEHOLDER}"
  awsSecretAccessKey: "${CATALOG_SECRET_KEY:-PLACEHOLDER}"
EOF

# MongoDB app user password
cat > "$CUSTOM_DIR/mongodb-app-users-secret.yaml" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: dremio-mongodb-app-users
  namespace: dremio
  annotations:
    helm.sh/resource-policy: keep
type: Opaque
stringData:
  dremio: "${DREMIO_MONGODB_PASSWORD:-PLACEHOLDER}"
EOF

# MongoDB system users
cat > "$CUSTOM_DIR/mongodb-system-users-secret.yaml" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: dremio-mongodb-system-users
  namespace: dremio
type: Opaque
stringData:
  MONGODB_CLUSTER_ADMIN_USER: clusterAdmin
  MONGODB_CLUSTER_ADMIN_PASSWORD: "${DREMIO_MONGODB_ADMIN_PASSWORD:-PLACEHOLDER}"
  MONGODB_CLUSTER_MONITOR_USER: clusterMonitor
  MONGODB_CLUSTER_MONITOR_PASSWORD: "${DREMIO_MONGODB_MONITOR_PASSWORD:-PLACEHOLDER}"
  MONGODB_BACKUP_USER: backup
  MONGODB_BACKUP_PASSWORD: "${DREMIO_MONGODB_BACKUP_PASSWORD:-PLACEHOLDER}"
  MONGODB_USER_ADMIN_USER: userAdmin
  MONGODB_USER_ADMIN_PASSWORD: "${DREMIO_MONGODB_USERADMIN_PASSWORD:-PLACEHOLDER}"
EOF

# MongoDB backup S3 credentials (same bucket as distStorage)
cat > "$CUSTOM_DIR/mongodb-backup-secret.yaml" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: dremio-mongodb-backup
  namespace: dremio
type: Opaque
stringData:
  AWS_ACCESS_KEY_ID: "${DIST_ACCESS_KEY:-PLACEHOLDER}"
  AWS_SECRET_ACCESS_KEY: "${DIST_SECRET_KEY:-PLACEHOLDER}"
EOF

# Dremio license
cat > "$CUSTOM_DIR/dremio-license-secret.yaml" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: dremio-license
  namespace: dremio
type: Opaque
stringData:
  license: "${DREMIO_LICENSE_KEY:-}"
EOF

echo "  Created: image-pull-secret.yaml"
echo "  Created: catalog-s3-secret.yaml"
echo "  Created: mongodb-app-users-secret.yaml"
echo "  Created: mongodb-system-users-secret.yaml"
echo "  Created: mongodb-backup-secret.yaml"
echo "  Created: dremio-license-secret.yaml"

# ============================================================================
# STEP 3: Render Helm templates with credentials from .env
# ============================================================================
echo ""
echo "Rendering Helm templates..."

helm template dremio "$CHART_DIR" \
    --namespace dremio \
    --values "$VALUES_BASE" \
    --values "$VALUES_ENV" \
    --set "distStorage.aws.credentials.accessKey=${DIST_ACCESS_KEY:-PLACEHOLDER}" \
    --set "distStorage.aws.credentials.secret=${DIST_SECRET_KEY:-PLACEHOLDER}" \
    --output-dir "$RENDERED_DIR/"

echo ""

# ============================================================================
# STEP 3b: Remove helm-generated secrets (replaced by custom/)
# ============================================================================
HELM_TEMPLATES_DIR="$RENDERED_DIR/dremio-helm/templates"

# Delete standalone secret files
for f in mongodb-backup.yaml dremio-license-secret.yaml dremio-trial-image-pull-credentials-secret.yaml; do
    if [[ -f "$HELM_TEMPLATES_DIR/$f" ]]; then
        rm "$HELM_TEMPLATES_DIR/$f"
        echo "Removed helm-generated $f (replaced by custom/)"
    fi
done

# Strip Secret documents from multi-doc files (e.g. mongodb.yaml)
for f in "$HELM_TEMPLATES_DIR"/*.yaml; do
    [[ -f "$f" ]] || continue
    if grep -q 'kind: Secret' "$f"; then
        # Remove YAML documents that contain "kind: Secret", keep the rest
        awk '
        BEGIN { doc=""; has_secret=0 }
        /^---/ {
            if (doc != "" && !has_secret) printf "%s", doc
            doc = $0 "\n"; has_secret = 0; next
        }
        { doc = doc $0 "\n" }
        /kind: Secret/ { has_secret = 1 }
        END { if (doc != "" && !has_secret) printf "%s", doc }
        ' "$f" > "$f.tmp"
        mv "$f.tmp" "$f"
        echo "Stripped Secret documents from $(basename "$f")"
    fi
done

TOTAL=$(find "$RENDERED_DIR" -name '*.yaml' | wc -l)
echo ""
echo "Rendered $TOTAL files to $RENDERED_DIR/"

# ============================================================================
# STEP 4: Report empty files
# ============================================================================
EMPTY_FILES=()
while IFS= read -r f; do
    if ! grep -qE '^[^#]' "$f" 2>/dev/null; then
        EMPTY_FILES+=("$f")
    fi
done < <(find "$RENDERED_DIR" -name '*.yaml' -type f -not -path "*/custom/*" | sort)

if [[ ${#EMPTY_FILES[@]} -gt 0 ]]; then
    echo ""
    echo "Empty templates (no K8s objects rendered):"
    for f in "${EMPTY_FILES[@]}"; do
        echo "  - ${f#$RENDERED_DIR/}"
    done
    if [[ "$CLEAN_EMPTY" == "true" ]]; then
        for f in "${EMPTY_FILES[@]}"; do
            rm "$f"
        done
        find "$RENDERED_DIR" -type d -empty -not -path "$CUSTOM_DIR" -delete 2>/dev/null || true
        echo ""
        echo "Deleted ${#EMPTY_FILES[@]} empty files (--clean)"
    fi
    echo ""
    echo "Active: $((TOTAL - ${#EMPTY_FILES[@]}))  |  Empty: ${#EMPTY_FILES[@]}  |  Total: $TOTAL"
fi
