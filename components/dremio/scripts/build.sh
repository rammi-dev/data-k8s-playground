#!/bin/bash
# Deploy Dremio Enterprise to the Kubernetes cluster using Helm
# Requires: Ceph S3 deployed (for distributed storage)
#
# Based on: https://github.com/rammi-dev/lakehouse-minikube
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
COMPONENT_DIR="$PROJECT_ROOT/components/dremio"
HELM_DIR="$COMPONENT_DIR/helm"

source "$PROJECT_ROOT/scripts/common/utils.sh"
source "$PROJECT_ROOT/scripts/common/config-loader.sh"

# Check if component is enabled
if [[ "$DREMIO_ENABLED" != "true" ]]; then
    print_error "Dremio is not enabled in config.yaml"
    print_info "Set 'components.dremio.enabled: true' in config.yaml"
    exit 1
fi

# Check if Kubernetes cluster is accessible
if ! kubectl cluster-info &>/dev/null; then
    print_error "Kubernetes cluster is not accessible"
    exit 1
fi

# Load .env for registry credentials and MongoDB password
ENV_FILE="$HELM_DIR/.env"
if [[ ! -f "$ENV_FILE" ]]; then
    print_error ".env file not found at $ENV_FILE"
    print_info "Copy .env.example to .env and fill in your credentials:"
    print_info "  cp $HELM_DIR/.env.example $HELM_DIR/.env"
    exit 1
fi

set -a
source "$ENV_FILE"
set +a

if [[ -z "$DREMIO_REGISTRY_USER" ]] || [[ -z "$DREMIO_REGISTRY_PASSWORD" ]]; then
    print_error "DREMIO_REGISTRY_USER and DREMIO_REGISTRY_PASSWORD must be set in .env"
    exit 1
fi

# Validate MongoDB passwords
for var in DREMIO_MONGODB_PASSWORD DREMIO_MONGODB_ADMIN_PASSWORD DREMIO_MONGODB_MONITOR_PASSWORD DREMIO_MONGODB_BACKUP_PASSWORD DREMIO_MONGODB_USERADMIN_PASSWORD; do
    if [[ -z "${!var}" ]] || [[ "${!var}" == "change-me-in-production" ]]; then
        print_error "$var must be set in .env"
        exit 1
    fi
done

print_info "Deploying Dremio Enterprise via Helm"
print_info "Namespace: $DREMIO_NAMESPACE"

# ============================================================================
# PRE-FLIGHT: Verify Ceph S3 is available
# ============================================================================
print_info "Verifying Ceph S3 is available..."
if ! kubectl -n "$CEPH_NAMESPACE" get cephobjectstore s3-store &>/dev/null; then
    print_error "Ceph S3 object store not found"
    print_info "Deploy Ceph first: ./components/ceph/scripts/build.sh"
    exit 1
fi

# ============================================================================
# PRE-FLIGHT: Create Dremio S3 users in Ceph
# ============================================================================
print_info "Applying Dremio S3 user manifests to Ceph..."
kubectl -n "$CEPH_NAMESPACE" apply -R -f "$HELM_DIR/templates/custom/"

# Wait for all Dremio S3 user secrets
print_info "Waiting for S3 user secrets..."
for user in dremio-dist dremio-catalog; do
    SECRET="rook-ceph-object-user-s3-store-$user"
    for i in {1..12}; do
        if kubectl -n "$CEPH_NAMESPACE" get secret "$SECRET" &>/dev/null; then
            print_success "  $user ready"
            break
        fi
        [[ "$i" -eq 12 ]] && { print_error "$user secret not ready after 60s"; exit 1; }
        sleep 5
    done
done

# ============================================================================
# PRE-FLIGHT: Retrieve S3 credentials (separate per component)
# ============================================================================
print_info "Retrieving S3 credentials..."

# Admin credentials (bucket management only)
ADMIN_ACCESS_KEY=$(kubectl -n "$CEPH_NAMESPACE" get secret \
    rook-ceph-object-user-s3-store-admin \
    -o jsonpath='{.data.AccessKey}' 2>/dev/null | base64 -d)
ADMIN_SECRET_KEY=$(kubectl -n "$CEPH_NAMESPACE" get secret \
    rook-ceph-object-user-s3-store-admin \
    -o jsonpath='{.data.SecretKey}' 2>/dev/null | base64 -d)

# distStorage credentials (coordinator, executor, MongoDB backup)
DIST_ACCESS_KEY=$(kubectl -n "$CEPH_NAMESPACE" get secret \
    rook-ceph-object-user-s3-store-dremio-dist \
    -o jsonpath='{.data.AccessKey}' 2>/dev/null | base64 -d)
DIST_SECRET_KEY=$(kubectl -n "$CEPH_NAMESPACE" get secret \
    rook-ceph-object-user-s3-store-dremio-dist \
    -o jsonpath='{.data.SecretKey}' 2>/dev/null | base64 -d)

# Catalog credentials (Polaris)
CATALOG_ACCESS_KEY=$(kubectl -n "$CEPH_NAMESPACE" get secret \
    rook-ceph-object-user-s3-store-dremio-catalog \
    -o jsonpath='{.data.AccessKey}' 2>/dev/null | base64 -d)
CATALOG_SECRET_KEY=$(kubectl -n "$CEPH_NAMESPACE" get secret \
    rook-ceph-object-user-s3-store-dremio-catalog \
    -o jsonpath='{.data.SecretKey}' 2>/dev/null | base64 -d)

# Validate all credentials
for var in ADMIN_ACCESS_KEY ADMIN_SECRET_KEY DIST_ACCESS_KEY DIST_SECRET_KEY CATALOG_ACCESS_KEY CATALOG_SECRET_KEY; do
    if [[ -z "${!var}" ]]; then
        print_error "Failed to retrieve $var from Ceph"
        exit 1
    fi
done
print_success "S3 credentials retrieved (admin, dremio-dist, dremio-catalog)"

# Create S3 buckets for Dremio (using admin credentials)
print_info "Creating S3 buckets for Dremio..."
kubectl -n "$CEPH_NAMESPACE" exec deploy/rook-ceph-tools -- bash -c "
    export AWS_ACCESS_KEY_ID='$ADMIN_ACCESS_KEY'
    export AWS_SECRET_ACCESS_KEY='$ADMIN_SECRET_KEY'
    export AWS_DEFAULT_REGION='us-east-1'
    RGW=http://rook-ceph-rgw-s3-store.$CEPH_NAMESPACE.svc:80

    # Install aws cli if not present
    if ! command -v aws &>/dev/null; then
        pip3 install -q awscli 2>/dev/null || true
    fi

    for bucket in dremio dremio-catalog; do
        if aws --endpoint-url \$RGW s3 ls s3://\$bucket 2>/dev/null; then
            echo \"Bucket \$bucket already exists\"
        else
            aws --endpoint-url \$RGW s3 mb s3://\$bucket 2>/dev/null && echo \"Created bucket \$bucket\" || echo \"Bucket \$bucket may already exist\"
        fi
    done
" 2>/dev/null || print_warning "Could not create buckets (may need to create manually)"

# ============================================================================
# STEP 1: Create namespace and secrets
# ============================================================================
print_info "Step 1: Creating namespace and secrets..."

kubectl create namespace "$DREMIO_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Image pull secret for quay.io
kubectl create secret docker-registry dremio-quay-secret \
    --docker-server="${DREMIO_REGISTRY:-quay.io}" \
    --docker-username="$DREMIO_REGISTRY_USER" \
    --docker-password="$DREMIO_REGISTRY_PASSWORD" \
    --docker-email="${DREMIO_REGISTRY_EMAIL:-no-reply@dremio.local}" \
    -n "$DREMIO_NAMESPACE" \
    --dry-run=client -o yaml | kubectl apply -f -

# Catalog S3 storage credentials (from dremio-catalog S3 user)
kubectl create secret generic catalog-server-s3-storage-creds \
    -n "$DREMIO_NAMESPACE" \
    --from-literal=awsAccessKeyId="$CATALOG_ACCESS_KEY" \
    --from-literal=awsSecretAccessKey="$CATALOG_SECRET_KEY" \
    --dry-run=client -o yaml | kubectl apply -f -

# MongoDB app user password (from .env — chart skips auto-generation if secret exists)
kubectl create secret generic dremio-mongodb-app-users \
    -n "$DREMIO_NAMESPACE" \
    --from-literal=dremio="$DREMIO_MONGODB_PASSWORD" \
    --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "$DREMIO_NAMESPACE" annotate secret dremio-mongodb-app-users \
    helm.sh/resource-policy=keep --overwrite

# MongoDB system users (from .env — operator uses existing secret instead of auto-generating)
kubectl create secret generic dremio-mongodb-system-users \
    -n "$DREMIO_NAMESPACE" \
    --from-literal=MONGODB_CLUSTER_ADMIN_USER=clusterAdmin \
    --from-literal=MONGODB_CLUSTER_ADMIN_PASSWORD="$DREMIO_MONGODB_ADMIN_PASSWORD" \
    --from-literal=MONGODB_CLUSTER_MONITOR_USER=clusterMonitor \
    --from-literal=MONGODB_CLUSTER_MONITOR_PASSWORD="$DREMIO_MONGODB_MONITOR_PASSWORD" \
    --from-literal=MONGODB_BACKUP_USER=backup \
    --from-literal=MONGODB_BACKUP_PASSWORD="$DREMIO_MONGODB_BACKUP_PASSWORD" \
    --from-literal=MONGODB_USER_ADMIN_USER=userAdmin \
    --from-literal=MONGODB_USER_ADMIN_PASSWORD="$DREMIO_MONGODB_USERADMIN_PASSWORD" \
    --dry-run=client -o yaml | kubectl apply -f -

print_success "  Namespace and secrets ready"

# ============================================================================
# STEP 2: Install Dremio via Helm (local chart)
# ============================================================================
print_info "Step 2: Installing Dremio..."

HELM_CMD="helm upgrade --install dremio $HELM_DIR/dremio \
    -n $DREMIO_NAMESPACE \
    -f $HELM_DIR/dremio/values.yaml \
    -f $HELM_DIR/values-overrides.yaml \
    --set distStorage.aws.credentials.accessKey=$DIST_ACCESS_KEY \
    --set distStorage.aws.credentials.secret=$DIST_SECRET_KEY \
    --set catalog.storage.s3.accessKey=$CATALOG_ACCESS_KEY \
    --set catalog.storage.s3.secretKey=$CATALOG_SECRET_KEY"

# Add license key if provided
if [[ -n "$DREMIO_LICENSE_KEY" ]] && [[ "$DREMIO_LICENSE_KEY" != "your-license-key-here" ]]; then
    HELM_CMD="$HELM_CMD --set dremio.license=$DREMIO_LICENSE_KEY"
    print_info "  License key provided"
else
    print_warning "  No license key - running in trial mode"
fi

HELM_CMD="$HELM_CMD --wait --timeout=15m"

eval $HELM_CMD

print_success "Dremio deployed!"
echo ""

# ============================================================================
# STATUS
# ============================================================================
print_info "Dremio Pods:"
kubectl -n "$DREMIO_NAMESPACE" get pods
echo ""
print_info "Next steps:"
print_info "  1. Access UI: ./components/dremio/scripts/dashboard.sh"
print_info "  2. Create admin user (first login)"
print_info "  3. Go to Settings -> Engines -> Add Engine"
print_info "     Size: Small (1 pod, 10Gi) | CPU: 1C | Offset: reserve-0-0"
