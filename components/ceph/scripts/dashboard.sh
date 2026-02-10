#!/bin/bash
# Display Ceph dashboard and S3 gateway access info
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$PROJECT_ROOT/scripts/common/utils.sh"
source "$PROJECT_ROOT/scripts/common/config-loader.sh"

# Get dashboard password
PASSWORD=$(kubectl -n "$CEPH_NAMESPACE" get secret rook-ceph-dashboard-password -o jsonpath='{.data.password}' 2>/dev/null | base64 -d)
if [[ -z "$PASSWORD" ]]; then
    print_error "Could not retrieve dashboard password"
    exit 1
fi

# Get S3 credentials
S3_ACCESS_KEY=$(kubectl -n "$CEPH_NAMESPACE" get secret rook-ceph-object-user-s3-store-admin -o jsonpath='{.data.AccessKey}' 2>/dev/null | base64 -d)
S3_SECRET_KEY=$(kubectl -n "$CEPH_NAMESPACE" get secret rook-ceph-object-user-s3-store-admin -o jsonpath='{.data.SecretKey}' 2>/dev/null | base64 -d)

DASHBOARD_PORT=7000
S3_PORT=7480

print_info "=== Ceph Dashboard ==="
echo "  URL:      http://localhost:$DASHBOARD_PORT"
echo "  User:     admin"
echo "  Password: $PASSWORD"
echo ""

print_info "=== S3 Gateway (RGW) ==="
if [[ -n "$S3_ACCESS_KEY" ]]; then
    echo "  Endpoint: http://localhost:$S3_PORT"
    echo ""
    echo "  AWS CLI usage:"
    echo "    export AWS_ACCESS_KEY_ID=$S3_ACCESS_KEY"
    echo "    export AWS_SECRET_ACCESS_KEY=$S3_SECRET_KEY"
    echo "    export AWS_ENDPOINT_URL=http://localhost:$S3_PORT"
    echo ""
    echo "    aws s3 ls"
    echo "    aws s3 mb s3://my-bucket"
    echo "    aws s3 cp file.txt s3://my-bucket/"
else
    print_warning "S3 admin user not found (deploy with build.sh)"
fi
echo ""

print_info "Starting port-forwards (Ctrl+C to stop)..."
kubectl -n "$CEPH_NAMESPACE" port-forward svc/rook-ceph-mgr-dashboard "$DASHBOARD_PORT:7000" &
kubectl -n "$CEPH_NAMESPACE" port-forward svc/rook-ceph-rgw-s3-store "$S3_PORT:80" &
wait
