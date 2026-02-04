#!/bin/bash
# Quick morning startup with health check
# Usage: ./vagrant.sh quickstart
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common/utils.sh"

print_info "Starting daily quick-start..."

# Try resume first (fast), fall back to start if not suspended
if run_vagrant status 2>/dev/null | grep -q "saved"; then
    print_info "Resuming from suspended state..."
    run_vagrant resume
else
    print_info "Starting VM..."
    run_vagrant up --no-provision
fi

# Wait for VM to be accessible
print_info "Waiting for VM to be ready..."
sleep 3

# Run health check inside VM
print_info "Running health check..."
run_vagrant ssh -c "cd /vagrant && ./scripts/minikube/health-check.sh" 2>/dev/null || {
    print_warning "Health check failed - minikube may need to be started"
    print_info "SSH into VM: ./vagrant.sh ssh"
    print_info "Start minikube: cd /vagrant && ./scripts/minikube/build.sh"
}

print_success "Quick-start complete!"
print_info "SSH into VM: ./vagrant.sh ssh"
