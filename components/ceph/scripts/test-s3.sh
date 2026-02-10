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

# Set up port-forward to RGW service (ClusterIP not reachable from WSL)
RGW_SVC=$(kubectl -n rook-ceph get svc -l app=rook-ceph-rgw -o name 2>/dev/null | head -1)
if [[ -z "$RGW_SVC" ]]; then
    print_error "Could not find RGW service"
    print_info "Available services:"
    kubectl -n rook-ceph get svc | grep rgw
    exit 1
fi

LOCAL_PORT=7480
print_info "Setting up port-forward ($RGW_SVC -> localhost:$LOCAL_PORT)..."
kubectl -n rook-ceph port-forward "$RGW_SVC" "$LOCAL_PORT:80" &>/dev/null &
PF_PID=$!
trap "kill $PF_PID 2>/dev/null" EXIT
sleep 2

# Verify port-forward is running
if ! kill -0 $PF_PID 2>/dev/null; then
    print_error "Port-forward failed to start"
    exit 1
fi

S3_ENDPOINT="http://localhost:$LOCAL_PORT"

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
    export AWS_DEFAULT_REGION="us-east-1"
    TEST_BUCKET="s3://test-bucket-$$"
    TEST_FILE=$(mktemp)
    echo "Hello from Ceph S3 test - $(date)" > "$TEST_FILE"

    # Step 1: Create bucket
    echo ""
    print_info "Step 1: Creating bucket ${TEST_BUCKET}..."
    if aws s3 mb "$TEST_BUCKET"; then
        print_success "Bucket created"
    else
        print_error "Failed to create bucket"
        rm -f "$TEST_FILE"
        kubectl -n rook-ceph get pods | grep rgw
        exit 1
    fi

    # Step 2: Upload test file
    print_info "Step 2: Uploading test file..."
    if aws s3 cp "$TEST_FILE" "$TEST_BUCKET/test.txt"; then
        print_success "File uploaded"
    else
        print_error "Failed to upload file"
        aws s3 rb "$TEST_BUCKET" --force 2>/dev/null || true
        rm -f "$TEST_FILE"
        exit 1
    fi

    # Step 3: List bucket contents
    print_info "Step 3: Listing bucket contents..."
    aws s3 ls "$TEST_BUCKET/"
    print_success "List OK"

    # Step 4: Download and verify
    print_info "Step 4: Downloading and verifying..."
    DL_FILE=$(mktemp)
    aws s3 cp "$TEST_BUCKET/test.txt" "$DL_FILE"
    if diff -q "$TEST_FILE" "$DL_FILE" &>/dev/null; then
        print_success "Downloaded file matches original"
    else
        print_warning "Downloaded file differs from original"
    fi
    rm -f "$DL_FILE"

    # Step 5: Delete file
    print_info "Step 5: Deleting test file..."
    aws s3 rm "$TEST_BUCKET/test.txt"
    print_success "File deleted"

    # Step 6: Remove bucket
    print_info "Step 6: Removing bucket..."
    aws s3 rb "$TEST_BUCKET"
    print_success "Bucket removed"

    rm -f "$TEST_FILE"
fi

echo ""
print_success "S3 test complete!"
print_info "Use these credentials for S3 access:"
echo "  AWS_ACCESS_KEY_ID=$ACCESS_KEY"
echo "  AWS_SECRET_ACCESS_KEY=<hidden>"
echo "  AWS_ENDPOINT_URL=$S3_ENDPOINT"
