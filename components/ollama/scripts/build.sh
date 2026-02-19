#!/bin/bash
# Deploy Ollama LLM inference server to the Kubernetes cluster using Helm
set -e

# Determine project root (works from any location)
if [[ -d "/vagrant" ]]; then
    PROJECT_ROOT="/vagrant"
elif [[ -n "${PROJECT_ROOT:-}" ]]; then
    : # Use existing PROJECT_ROOT
else
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
fi

COMPONENT_DIR="$PROJECT_ROOT/components/ollama"
HELM_DIR="$COMPONENT_DIR/helm"

source "$PROJECT_ROOT/scripts/common/utils.sh"
source "$PROJECT_ROOT/scripts/common/config-loader.sh"

RELEASE_NAME="ollama"

# Check if component is enabled
if [[ "$OLLAMA_ENABLED" != "true" ]]; then
    print_error "Ollama is not enabled in config.yaml"
    print_info "Set 'components.ollama.enabled: true' in config.yaml"
    exit 1
fi

# Check if Kubernetes cluster is accessible
if ! kubectl cluster-info &>/dev/null; then
    print_error "Kubernetes cluster is not accessible"
    print_info "Make sure kubectl is configured and the cluster is running"
    exit 1
fi

print_info "Deploying Ollama (chart v${OLLAMA_CHART_VERSION})"
echo "=========================================="

# Create namespace if it doesn't exist
print_info "Creating namespace: ${OLLAMA_NAMESPACE}"
kubectl create namespace "${OLLAMA_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

# Add Helm repository
print_info "Adding OTWLD Helm repository..."
helm repo add otwld "$OLLAMA_CHART_REPO" 2>/dev/null || true
helm repo update

# Update chart dependencies
print_info "Updating chart dependencies..."
helm dependency update "$HELM_DIR"

# Install or upgrade Ollama
print_info "Installing/upgrading Ollama..."
helm upgrade --install ${RELEASE_NAME} "$HELM_DIR" \
    --namespace "${OLLAMA_NAMESPACE}" \
    --values "$HELM_DIR/values.yaml" \
    --timeout 600s

print_info "Waiting for pods to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=ollama -n "${OLLAMA_NAMESPACE}" --timeout=300s || true

print_success "Ollama Deployed!"
echo "=========================================="

echo ""
print_info "Model '${OLLAMA_MODEL}' will be pulled on first startup (may take a few minutes)"

echo ""
print_info "To access Ollama API:"
echo "  kubectl port-forward svc/${RELEASE_NAME} -n ${OLLAMA_NAMESPACE} 11434:11434"
echo "  curl http://localhost:11434/api/tags"

echo ""
print_info "To chat:"
echo "  curl http://localhost:11434/api/generate -d '{\"model\": \"${OLLAMA_MODEL}\", \"prompt\": \"Hello\"}'"

echo ""
print_info "To upgrade: edit helm/values.yaml and re-run this script"
