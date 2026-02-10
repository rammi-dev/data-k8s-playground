#!/bin/bash
# Network Performance Test Script for Vagrant VM
# Run this inside the VM to verify network configuration
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common/utils.sh"

print_info "=== Vagrant VM Network Performance Test ==="
echo ""

# Test 1: Network Interfaces
print_info "1. Network Interfaces:"
ip addr show | grep -E "^[0-9]+:|inet " | grep -v "127.0.0.1"
echo ""

# Test 2: MTU Configuration
print_info "2. MTU Configuration:"
for iface in $(ip -o link show | awk -F': ' '{print $2}' | grep -E '^eth|^enp'); do
    mtu=$(ip link show "$iface" | grep -oP 'mtu \K[0-9]+')
    echo "  $iface: MTU $mtu"
done
echo ""

# Test 3: DNS Resolution Speed
print_info "3. DNS Resolution Test:"
echo -n "  Resolving google.com... "
start=$(date +%s%N)
nslookup google.com > /dev/null 2>&1
end=$(date +%s%N)
elapsed=$(( (end - start) / 1000000 ))
echo "${elapsed}ms"

if [ $elapsed -lt 100 ]; then
    print_success "  ✓ DNS resolution is fast (< 100ms)"
elif [ $elapsed -lt 500 ]; then
    print_warning "  ⚠ DNS resolution is acceptable (100-500ms)"
else
    print_error "  ✗ DNS resolution is slow (> 500ms)"
fi
echo ""

# Test 4: Network Sysctls
print_info "4. Network Performance Sysctls:"
echo "  TCP receive buffer max: $(sysctl -n net.core.rmem_max 2>/dev/null || echo 'not set')"
echo "  TCP send buffer max: $(sysctl -n net.core.wmem_max 2>/dev/null || echo 'not set')"
echo "  Congestion control: $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo 'not set')"
echo "  Queue discipline: $(sysctl -n net.core.default_qdisc 2>/dev/null || echo 'not set')"
echo ""

# Test 5: Docker Configuration
print_info "5. Docker Daemon Configuration:"
if [ -f /etc/docker/daemon.json ]; then
    echo "  DNS servers: $(jq -r '.dns[]' /etc/docker/daemon.json 2>/dev/null | tr '\n' ', ' | sed 's/,$//')"
    echo "  MTU: $(jq -r '.mtu' /etc/docker/daemon.json 2>/dev/null)"
    echo "  Max concurrent downloads: $(jq -r '.["max-concurrent-downloads"]' /etc/docker/daemon.json 2>/dev/null)"
    echo "  Max concurrent uploads: $(jq -r '.["max-concurrent-uploads"]' /etc/docker/daemon.json 2>/dev/null)"
else
    print_warning "  Docker daemon.json not found"
fi
echo ""

# Test 6: Docker Network MTU
print_info "6. Docker Bridge Network:"
if command -v docker &> /dev/null && docker info &> /dev/null; then
    bridge_mtu=$(docker network inspect bridge -f '{{.Options."com.docker.network.driver.mtu"}}' 2>/dev/null || echo "default")
    echo "  Bridge MTU: $bridge_mtu"
else
    print_warning "  Docker not running"
fi
echo ""

# Test 7: Download Speed Test
print_info "7. Download Speed Test:"
echo -n "  Downloading test file (10MB)... "
start=$(date +%s)
curl -s -o /dev/null -w "%{speed_download}" https://speed.hetzner.de/10MB.bin 2>/dev/null || echo "0"
end=$(date +%s)
elapsed=$((end - start))
echo " (${elapsed}s)"

if [ $elapsed -lt 5 ]; then
    print_success "  ✓ Download speed is good (< 5s for 10MB)"
elif [ $elapsed -lt 15 ]; then
    print_warning "  ⚠ Download speed is acceptable (5-15s for 10MB)"
else
    print_error "  ✗ Download speed is slow (> 15s for 10MB)"
fi
echo ""

# Test 8: Docker Image Pull Test (if Docker is running)
if command -v docker &> /dev/null && docker info &> /dev/null; then
    print_info "8. Docker Image Pull Test:"
    echo "  Pulling nginx:alpine (small image)..."
    start=$(date +%s)
    docker pull nginx:alpine > /dev/null 2>&1 || true
    end=$(date +%s)
    elapsed=$((end - start))
    echo "  Time: ${elapsed}s"
    
    if [ $elapsed -lt 30 ]; then
        print_success "  ✓ Image pull is fast (< 30s)"
    elif [ $elapsed -lt 60 ]; then
        print_warning "  ⚠ Image pull is acceptable (30-60s)"
    else
        print_error "  ✗ Image pull is slow (> 60s)"
    fi
    
    # Clean up
    docker rmi nginx:alpine > /dev/null 2>&1 || true
    echo ""
fi

# Test 9: VirtualBox Network Adapter Type
print_info "9. Network Adapter Information:"
# Try to detect adapter type from dmesg or lspci
if lspci 2>/dev/null | grep -i "ethernet" | grep -i "virtio" > /dev/null; then
    print_success "  ✓ Using virtio-net adapter (optimal)"
elif lspci 2>/dev/null | grep -i "ethernet" | grep -i "82540EM" > /dev/null; then
    print_warning "  ⚠ Using 82540EM adapter (slower, consider upgrading to virtio-net)"
else
    adapter=$(lspci 2>/dev/null | grep -i "ethernet" | head -1 || echo "Unknown")
    echo "  Adapter: $adapter"
fi
echo ""

# Summary
print_info "=== Test Summary ==="
print_info "Network configuration test complete!"
print_info ""
print_info "Expected optimal values:"
print_info "  - DNS resolution: < 100ms"
print_info "  - Download speed: < 5s for 10MB"
print_info "  - Docker image pull: < 30s for small images"
print_info "  - TCP buffers: 134217728 (128MB)"
print_info "  - Congestion control: bbr"
print_info "  - Network adapter: virtio-net"
