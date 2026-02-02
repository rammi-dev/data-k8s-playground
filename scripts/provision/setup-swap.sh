#!/bin/bash
# Setup swap space for memory safety
# This prevents system freezes when memory runs low
set -e

SWAP_SIZE="${1:-4G}"  # Default 4GB swap

echo "=== Setting up ${SWAP_SIZE} swap space ==="

# Check if swap already exists
if swapon --show | grep -q '/swapfile'; then
    echo "Swap already configured:"
    swapon --show
    exit 0
fi

# Create swap file
fallocate -l ${SWAP_SIZE} /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile

# Make persistent across reboots
if ! grep -q '/swapfile' /etc/fstab; then
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

# Optimize swap settings for this use case
# swappiness=10 means only swap when really needed
echo 'vm.swappiness=10' >> /etc/sysctl.conf
sysctl vm.swappiness=10

echo "=== Swap configured ==="
free -h
