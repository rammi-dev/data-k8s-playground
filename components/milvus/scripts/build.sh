#!/bin/bash
# Deploy Milvus vector database to the Kubernetes cluster using Helm
# Requires: Ceph deployed (block storage + S3 object store)
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
COMPONENT_DIR="$PROJECT_ROOT/components/milvus"
HELM_DIR="$COMPONENT_DIR/helm"

source "$PROJECT_ROOT/scripts/common/utils.sh"
source "$PROJECT_ROOT/scripts/common/config-loader.sh"

# Check if component is enabled
if [[ "$MILVUS_ENABLED" != "true" ]]; then
    print_error "Milvus is not enabled in config.yaml"
    print_info "Set 'components.milvus.enabled: true' in config.yaml"
    exit 1
fi

# Check if Kubernetes cluster is accessible
if ! kubectl cluster-info &>/dev/null; then
    print_error "Kubernetes cluster is not accessible"
    exit 1
fi

print_info "Deploying Milvus ${MILVUS_VERSION} (mode: ${MILVUS_MODE}, chart: ${MILVUS_CHART_VERSION})"
print_info "Namespace: $MILVUS_NAMESPACE"
echo "=========================================="

# ============================================================================
# PRE-FLIGHT: Verify Ceph StorageClass + S3
# ============================================================================
print_info "Verifying Ceph StorageClass is available..."
if ! kubectl get sc ceph-block &>/dev/null; then
    print_error "StorageClass 'ceph-block' not found"
    print_info "Deploy Ceph first: ./components/ceph/scripts/build.sh"
    exit 1
fi
print_success "  StorageClass ceph-block available"

print_info "Verifying Ceph S3 object store..."
if ! kubectl -n "$CEPH_NAMESPACE" get cephobjectstore s3-store &>/dev/null; then
    print_error "Ceph S3 object store not found"
    print_info "Deploy Ceph first: ./components/ceph/scripts/build.sh"
    exit 1
fi
print_success "  Ceph S3 object store available"

# ============================================================================
# STEP 1: Create Milvus S3 user in Ceph
# ============================================================================
print_info "Step 1: Creating Milvus S3 user..."
kubectl apply -f "$COMPONENT_DIR/manifests/s3-user.yaml"

S3_SECRET="rook-ceph-object-user-s3-store-milvus"
for i in {1..12}; do
    if kubectl -n "$CEPH_NAMESPACE" get secret "$S3_SECRET" &>/dev/null; then
        print_success "  S3 user ready"
        break
    fi
    [[ "$i" -eq 12 ]] && { print_error "S3 user secret not ready after 60s"; exit 1; }
    sleep 5
done

# ============================================================================
# STEP 2: Retrieve S3 credentials and create bucket
# ============================================================================
print_info "Step 2: Retrieving S3 credentials..."
S3_ACCESS_KEY=$(kubectl -n "$CEPH_NAMESPACE" get secret "$S3_SECRET" \
    -o jsonpath='{.data.AccessKey}' | base64 -d)
S3_SECRET_KEY=$(kubectl -n "$CEPH_NAMESPACE" get secret "$S3_SECRET" \
    -o jsonpath='{.data.SecretKey}' | base64 -d)

if [[ -z "$S3_ACCESS_KEY" ]] || [[ -z "$S3_SECRET_KEY" ]]; then
    print_error "Failed to retrieve S3 credentials"
    exit 1
fi
print_success "  S3 credentials retrieved"

print_info "  Creating S3 bucket 'milvus'..."
kubectl -n "$CEPH_NAMESPACE" exec deploy/rook-ceph-tools -- bash -c "
    export AWS_ACCESS_KEY_ID='$S3_ACCESS_KEY'
    export AWS_SECRET_ACCESS_KEY='$S3_SECRET_KEY'
    export AWS_DEFAULT_REGION='us-east-1'
    RGW=http://rook-ceph-rgw-s3-store.$CEPH_NAMESPACE.svc:80

    if ! command -v aws &>/dev/null; then
        pip3 install -q awscli 2>/dev/null || true
    fi

    if aws --endpoint-url \$RGW s3 ls s3://milvus 2>/dev/null; then
        echo 'Bucket milvus already exists'
    else
        aws --endpoint-url \$RGW s3 mb s3://milvus && echo 'Created bucket milvus'
    fi
" 2>/dev/null || print_warning "Could not create bucket (may need to create manually)"

# ============================================================================
# STEP 3: Create namespace
# ============================================================================
print_info "Step 3: Creating namespace..."
kubectl create namespace "$MILVUS_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
print_success "  Namespace $MILVUS_NAMESPACE ready"

# ============================================================================
# STEP 4: Install Milvus via Helm
# ============================================================================
print_info "Step 4: Installing Milvus..."

helm repo add zilliztech "$MILVUS_CHART_REPO" 2>/dev/null || true
helm repo update

print_info "  Updating chart dependencies..."
helm dependency update "$HELM_DIR"

helm upgrade --install milvus "$HELM_DIR" \
    -n "$MILVUS_NAMESPACE" \
    -f "$HELM_DIR/values.yaml" \
    --set "milvus.externalS3.accessKey=$S3_ACCESS_KEY" \
    --set "milvus.externalS3.secretKey=$S3_SECRET_KEY" \
    --wait --timeout=600s

print_success "  Helm release installed"

# ============================================================================
# STEP 5: Wait for Milvus to be ready
# ============================================================================
print_info "Step 5: Waiting for Milvus to be ready..."

if [[ "$MILVUS_MODE" == "standalone" ]]; then
    kubectl rollout status deployment/milvus-standalone -n "$MILVUS_NAMESPACE" --timeout=300s 2>/dev/null || \
    kubectl rollout status statefulset/milvus-standalone -n "$MILVUS_NAMESPACE" --timeout=300s 2>/dev/null || true
else
    # Cluster mode — wait for proxy
    kubectl rollout status deployment/milvus-proxy -n "$MILVUS_NAMESPACE" --timeout=300s 2>/dev/null || true
fi

print_success "  Milvus ready"

# ============================================================================
# STATUS
# ============================================================================
print_success "Milvus Deployed!"
echo "=========================================="
echo ""
print_info "Milvus Pods:"
kubectl -n "$MILVUS_NAMESPACE" get pods
echo ""
print_info "gRPC:  milvus.${MILVUS_NAMESPACE}.svc.cluster.local:19530"
print_info "S3:    rook-ceph-rgw-s3-store.${CEPH_NAMESPACE}.svc:80 (bucket: milvus)"
echo ""
print_info "Next steps:"
print_info "  1. Port-forward:  kubectl -n $MILVUS_NAMESPACE port-forward svc/milvus 19530:19530"
print_info "  2. Connect:       pymilvus → MilvusClient('http://localhost:19530')"
