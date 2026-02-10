#!/bin/bash
# Test S3 connectivity
# Run from inside the VM: cd /vagrant && ./components/ceph/scripts/test-s3.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$PROJECT_ROOT/scripts/common/utils.sh"

print_info "=== Testing S3 Connectivity ==="

# Check if aws CLI is available, install if not
if ! command -v aws &>/dev/null; then
    print_info "AWS CLI not found, installing..."

    # Check if we can install (need curl and unzip)
    if command -v curl &>/dev/null && command -v unzip &>/dev/null; then
        TMPDIR=$(mktemp -d)
        cd "$TMPDIR"

        if curl -sL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" && \
           unzip -q awscliv2.zip && \
           sudo ./aws/install --update 2>/dev/null; then
            print_success "AWS CLI v2 installed successfully"
            cd - >/dev/null
            rm -rf "$TMPDIR"
        else
            print_warning "Could not install AWS CLI, falling back to curl-based test"
            cd - >/dev/null
            rm -rf "$TMPDIR"
            USE_CURL=true
        fi
    else
        print_warning "curl or unzip not available, falling back to curl-based test"
        USE_CURL=true
    fi
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

S3_ENDPOINT="http://$ENDPOINT"

print_info "Endpoint: $S3_ENDPOINT"
print_info "Access Key: ${ACCESS_KEY:0:5}..."

# Use curl-based test if AWS CLI not available
if [[ "${USE_CURL:-}" == "true" ]]; then
    echo ""
    print_info "Testing S3 with curl..."

    # Simple GET request to check if RGW is responding
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$S3_ENDPOINT" 2>/dev/null || echo "000")

    if [[ "$HTTP_CODE" == "200" ]] || [[ "$HTTP_CODE" == "403" ]] || [[ "$HTTP_CODE" == "404" ]]; then
        print_success "S3 gateway is responding (HTTP $HTTP_CODE) ✅"
        print_info "Note: Install AWS CLI for full S3 testing:"
        print_info "  curl -sL 'https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip' -o awscliv2.zip && unzip awscliv2.zip && sudo ./aws/install"
    else
        print_error "S3 gateway not responding (HTTP $HTTP_CODE) ❌"
        print_info "RGW may still be initializing. Check pod status:"
        kubectl -n rook-ceph get pods | grep rgw
        exit 1
    fi
else
    export AWS_ACCESS_KEY_ID="$ACCESS_KEY"
    export AWS_SECRET_ACCESS_KEY="$SECRET_KEY"
    export AWS_ENDPOINT_URL="$S3_ENDPOINT"

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
fi

echo ""
print_success "S3 test complete!"
print_info "Use these credentials for S3 access:"
echo "  AWS_ACCESS_KEY_ID=$ACCESS_KEY"
echo "  AWS_SECRET_ACCESS_KEY=<hidden>"
echo "  AWS_ENDPOINT_URL=$S3_ENDPOINT"
