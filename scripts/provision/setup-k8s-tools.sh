#!/bin/bash
# Setup Kubernetes CLI tools: kubectx, kubens, and aliases/completions
# This script is run during VM provisioning
set -e

echo "=== Installing kubectx and kubens ==="
curl -fsSL https://github.com/ahmetb/kubectx/releases/latest/download/kubectx -o /usr/local/bin/kubectx
curl -fsSL https://github.com/ahmetb/kubectx/releases/latest/download/kubens -o /usr/local/bin/kubens
chmod +x /usr/local/bin/kubectx /usr/local/bin/kubens

echo "=== Setting up kubectl alias and completions ==="
# Install kubectx/kubens bash completions
curl -fsSL https://raw.githubusercontent.com/ahmetb/kubectx/master/completion/kubectx.bash -o /etc/bash_completion.d/kubectx
curl -fsSL https://raw.githubusercontent.com/ahmetb/kubectx/master/completion/kubens.bash -o /etc/bash_completion.d/kubens

# Add to vagrant user's .bashrc for interactive shells
BASHRC_BLOCK='
# Kubernetes aliases and completions
alias k="kubectl"
source <(kubectl completion bash 2>/dev/null)
complete -o default -F __start_kubectl k 2>/dev/null
source <(helm completion bash 2>/dev/null)
source <(minikube completion bash 2>/dev/null)
'

# Add to vagrant user's bashrc if not already present
if ! grep -q "alias k=" /home/vagrant/.bashrc 2>/dev/null; then
    echo "$BASHRC_BLOCK" >> /home/vagrant/.bashrc
    chown vagrant:vagrant /home/vagrant/.bashrc
fi

echo "=== K8s tools setup complete ==="
echo "Available commands: k (kubectl alias), kubectx, kubens"
