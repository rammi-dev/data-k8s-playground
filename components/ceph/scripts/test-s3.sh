#!/bin/bash
# Test S3 connectivity
# Run from inside the VM: cd /vagrant && ./components/ceph/scripts/test-s3.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$PROJECT_ROOT/scripts/common/utils.sh"

print_info "=== Testing S3 Connectivity ==="

# Check if aws CLI is available
if ! command -v aws &>/dev/null; then
    print_error "AWS CLI not installed"
    print_info "Install with: sudo apt-get install -y awscli"
    exit 1
fi

# Check if object store exists
if ! kubectl -n rook-ceph get cephobjectstore s3-store &>/dev/null; then
    print_error "Object store 's3-store' not found"
    print_info "Deploy Ceph first: ./components/ceph/scripts/build.sh"
    exit 1
fi

# Get S3 credentials from secret
print_info "Getting S3 credentials..."
SECRET_NAME=$(kubectl -n rook-ceph get secret -l app=rook-ceph-rgw -o name 2>/dev/null | head -1)
if [[ -z "$SECRET_NAME" ]]; then
    # Try the admin user secret
    SECRET_NAME="secret/rook-ceph-object-user-s3-store-admin"
fi

ACCESS_KEY=$(kubectl -n rook-ceph get "$SECRET_NAME" -o jsonpath='{.data.AccessKey}' 2>/dev/null | base64 -d)
SECRET_KEY=$(kubectl -n rook-ceph get "$SECRET_NAME" -o jsonpath='{.data.SecretKey}' 2>/dev/null | base64 -d)

if [[ -z "$ACCESS_KEY" ]] || [[ -z "$SECRET_KEY" ]]; then
    print_error "Could not retrieve S3 credentials"
    print_info "Secret: $SECRET_NAME"
    print_info "Available secrets:"
    kubectl -n rook-ceph get secrets | grep -i object
    exit 1
fi

# Get S3 endpoint
ENDPOINT=$(kubectl -n rook-ceph get svc rook-ceph-rgw-s3-store -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
if [[ -z "$ENDPOINT" ]]; then
    print_error "Could not find RGW service endpoint"
    print_info "Available services:"
    kubectl -n rook-ceph get svc | grep rgw
    exit 1
fi

export AWS_ACCESS_KEY_ID="$ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$SECRET_KEY"
export AWS_ENDPOINT_URL="http://$ENDPOINT"

print_info "Endpoint: $AWS_ENDPOINT_URL"
print_info "Access Key: ${ACCESS_KEY:0:5}..."

# Test listing buckets
echo ""
print_info "Testing S3 list buckets..."
if aws s3 ls --no-sign-request 2>/dev/null || aws s3 ls 2>/dev/null; then
    print_success "S3 connection working! ✅"
else
    print_warning "S3 list failed, trying to create a test bucket..."
    
    # Try creating a bucket
    if aws s3 mb s3://test-bucket 2>/dev/null; then
        print_success "Created test bucket successfully! ✅"
        aws s3 ls
        
        # Clean up
        print_info "Cleaning up test bucket..."
        aws s3 rb s3://test-bucket 2>/dev/null || true
    else
        print_error "S3 connection failed ❌"
        print_info "RGW may still be initializing. Check pod status:"
        kubectl -n rook-ceph get pods | grep rgw
        exit 1
    fi
fi

echo ""
print_success "S3 test complete!"
print_info "Use these credentials for S3 access:"
echo "  AWS_ACCESS_KEY_ID=$ACCESS_KEY"
echo "  AWS_SECRET_ACCESS_KEY=<hidden>"
echo "  AWS_ENDPOINT_URL=$AWS_ENDPOINT_URL"
