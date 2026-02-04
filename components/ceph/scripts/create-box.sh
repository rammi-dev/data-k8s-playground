#!/bin/bash
# Create a platform box with Ceph pre-deployed
# Run from WSL: ./components/ceph/scripts/create-box.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$PROJECT_ROOT/scripts/common/utils.sh"
source "$PROJECT_ROOT/scripts/common/config-loader.sh"

BOX_NAME="${1:-data-playground-ceph}"

print_info "Creating platform box with Ceph pre-deployed: $BOX_NAME"
print_warning "This will take 10-20 minutes and create a ~10GB box file"

# Check VM is running
if ! run_vagrant status 2>/dev/null | grep -q "running"; then
    print_error "VM must be running"
    print_info "Start with: ./scripts/vagrant/vagrant.sh start"
    exit 1
fi

# Deploy minikube inside VM
print_info "Step 1/4: Starting minikube..."
run_vagrant ssh -c "cd /vagrant && ./scripts/minikube/build.sh" || {
    print_error "Minikube setup failed"
    exit 1
}

# Enable Ceph in config temporarily (for build script)
print_info "Step 2/4: Deploying Ceph..."
run_vagrant ssh -c "cd /vagrant && CEPH_ENABLED=true ./components/ceph/scripts/build.sh" || {
    print_warning "Ceph deployment had issues, checking status..."
}

# Verify Ceph
print_info "Step 3/4: Verifying Ceph deployment..."
run_vagrant ssh -c "cd /vagrant && ./components/ceph/scripts/status.sh" || true

# Package the box
print_info "Step 4/4: Packaging platform box..."
"$PROJECT_ROOT/scripts/vagrant/vagrant.sh" package "$BOX_NAME"

print_success "Platform box created: $BOX_NAME"
echo ""
print_info "To use this box:"
print_info "  ./scripts/vagrant/vagrant.sh destroy data-playground"
print_info "  ./scripts/vagrant/vagrant.sh build --box $BOX_NAME"
echo ""
print_info "Box file: $PROJECT_ROOT/scripts/vagrant/${BOX_NAME}.box"

