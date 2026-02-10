#!/bin/bash
# Completely remove Rook-Ceph from the Kubernetes cluster
# Removes: cluster, operator, CRDs, namespace, disk data, and rook state
# Works from WSL with Hyper-V minikube or inside Vagrant VM
#
# Handles stuck resources by removing finalizers before deletion.
# Zaps bluestore signatures from disks so build.sh can start fresh.
set -e

# Determine project root (works from any location)
if [[ -d "/vagrant" ]]; then
    PROJECT_ROOT="/vagrant"
elif [[ -n "${PROJECT_ROOT:-}" ]]; then
    : # Use existing PROJECT_ROOT
else
    # Fallback: calculate from script location
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
fi

source "$PROJECT_ROOT/scripts/common/utils.sh"
source "$PROJECT_ROOT/scripts/common/config-loader.sh"

# Check if Kubernetes cluster is accessible
if ! kubectl cluster-info &>/dev/null; then
    print_error "Kubernetes cluster is not accessible"
    exit 1
fi

print_warning "This will completely remove Ceph (cluster + operator + disk data)!"
read -p "Are you sure? (y/N): " confirm

if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    print_info "Aborted."
    exit 0
fi

print_info "Removing Rook-Ceph..."

# Helper: remove finalizers from all objects of a given CRD in the namespace
remove_finalizers() {
    local crd="$1"
    for obj in $(kubectl -n "$CEPH_NAMESPACE" get "$crd" -o name 2>/dev/null); do
        print_info "  Removing finalizers from $obj..."
        kubectl -n "$CEPH_NAMESPACE" patch "$obj" --type merge -p '{"metadata":{"finalizers":null}}' 2>/dev/null || true
    done
}

# Step 1: Scale down operator (prevents it from recreating resources during cleanup)
print_info "Step 1: Scaling down Rook operator..."
kubectl -n "$CEPH_NAMESPACE" scale deploy/rook-ceph-operator --replicas=0 2>/dev/null || true
kubectl -n "$CEPH_NAMESPACE" wait --for=delete pod -l app=rook-ceph-operator --timeout=60s 2>/dev/null || true

# Step 2: Uninstall cluster Helm release
print_info "Step 2: Uninstalling Ceph cluster Helm release..."
if helm status rook-ceph-cluster -n "$CEPH_NAMESPACE" &>/dev/null; then
    # Start helm uninstall in background (may hang on finalizers)
    timeout 60 helm uninstall rook-ceph-cluster -n "$CEPH_NAMESPACE" --no-hooks 2>/dev/null &
    HELM_PID=$!

    # While helm is running, remove finalizers that block deletion
    sleep 5
    for crd in $(kubectl get crd -o name 2>/dev/null | grep 'ceph\.rook\.io'); do
        remove_finalizers "$(basename "$crd")"
    done

    wait $HELM_PID 2>/dev/null || true
    print_success "  Cluster chart uninstalled"
else
    print_info "  Cluster chart not installed, skipping"
fi

# Step 3: Remove finalizers from any remaining Ceph CRD objects (ceph.rook.io, csi.ceph.io, objectbucket.io)
print_info "Step 3: Removing finalizers from remaining resources..."
for crd in $(kubectl get crd -o name 2>/dev/null | grep -E 'ceph\.rook\.io|csi\.ceph\.io|objectbucket\.io'); do
    remove_finalizers "$(basename "$crd")"
done

# Step 4: Delete remaining Ceph CRD objects
print_info "Step 4: Deleting Ceph resources..."
for crd in $(kubectl get crd -o name 2>/dev/null | grep -E 'ceph\.rook\.io|csi\.ceph\.io|objectbucket\.io'); do
    kubectl -n "$CEPH_NAMESPACE" delete "$(basename "$crd")" --all --timeout=30s 2>/dev/null || true
done

# Step 5: Delete PVCs and StorageClasses
print_info "Step 5: Deleting PVCs and StorageClasses..."
kubectl -n "$CEPH_NAMESPACE" delete pvc --all --timeout=30s 2>/dev/null || true
kubectl delete storageclass ceph-block ceph-filesystem ceph-bucket 2>/dev/null || true

# Step 6: Delete operator-managed state (survives helm uninstall, causes stale mon issues)
# These secrets/configmaps may have disaster-protection finalizers
print_info "Step 6: Deleting operator-managed state..."
for obj in secret/rook-ceph-mon secret/rook-ceph-config cm/rook-ceph-mon-endpoints cm/rook-ceph-csi-config cm/rook-ceph-csi-mapping-config cm/rook-ceph-pdbstatemap; do
    kubectl -n "$CEPH_NAMESPACE" patch "$obj" --type merge -p '{"metadata":{"finalizers":null}}' 2>/dev/null || true
    kubectl -n "$CEPH_NAMESPACE" delete "$obj" --timeout=10s 2>/dev/null || true
done

# Step 7: Uninstall operator Helm release
print_info "Step 7: Uninstalling Rook operator Helm release..."
if helm status rook-ceph-operator -n "$CEPH_NAMESPACE" &>/dev/null; then
    helm uninstall rook-ceph-operator -n "$CEPH_NAMESPACE" --timeout=60s 2>/dev/null || true
    print_success "  Operator chart uninstalled"
else
    print_info "  Operator chart not installed, skipping"
fi

# Step 8: Delete namespace BEFORE CRDs (so API server can still resolve CRD resources during cleanup)
print_info "Step 8: Deleting namespace..."
if kubectl get namespace "$CEPH_NAMESPACE" &>/dev/null; then
    kubectl delete namespace "$CEPH_NAMESPACE" --timeout=60s 2>/dev/null || {
        # Namespace stuck in Terminating - force-remove the kubernetes finalizer
        print_warning "  Namespace stuck in Terminating, removing finalizer..."
        kubectl get namespace "$CEPH_NAMESPACE" -o json \
            | python3 -c 'import sys,json; ns=json.load(sys.stdin); ns["spec"]["finalizers"]=[]; json.dump(ns,sys.stdout)' \
            | kubectl replace --raw "/api/v1/namespaces/$CEPH_NAMESPACE/finalize" -f - 2>/dev/null || true
        # Wait for namespace to disappear
        for i in $(seq 1 12); do
            kubectl get namespace "$CEPH_NAMESPACE" &>/dev/null || break
            sleep 5
        done
    }
    print_success "  Namespace deleted"
else
    print_info "  Namespace not found, skipping"
fi

# Step 9: Delete Ceph CRDs (Helm does not remove CRDs on uninstall)
print_info "Step 9: Deleting Ceph CRDs..."
for crd in $(kubectl get crd -o name 2>/dev/null | grep -E 'ceph\.rook\.io|csi\.ceph\.io|objectbucket\.io'); do
    kubectl delete "$crd" --timeout=30s 2>/dev/null || true
done

# Step 10: Zap Ceph disks and clean rook data on all nodes
# Removes bluestore signatures so devices can be reused by a fresh cluster
print_info "Step 10: Zapping disks and cleaning rook data on all nodes..."
for node in $(kubectl get nodes -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
    print_info "  Creating cleanup job on $node..."
    cat <<EOF | kubectl apply -f - 2>/dev/null
apiVersion: batch/v1
kind: Job
metadata:
  name: ceph-cleanup-${node}
  namespace: default
spec:
  template:
    spec:
      restartPolicy: Never
      tolerations:
        - operator: Exists
      containers:
      - name: cleanup
        image: quay.io/ceph/ceph:v20
        securityContext:
          privileged: true
        command: ["/bin/bash", "-c"]
        args:
        - |
          echo "=== Cleaning Ceph data on ${node} ==="
          for dev in /dev/sda /dev/sdb /dev/sdc; do
            if [ ! -b "\$dev" ]; then continue; fi
            # Skip boot/mounted disks
            MOUNTS=\$(lsblk -n -o MOUNTPOINT "\$dev" 2>/dev/null | grep -c '/' || true)
            if [ "\$MOUNTS" -gt 0 ]; then
              echo "Skipping \$dev (has mounted partitions)"
              continue
            fi
            # Wipe entire device (bluestore labels are at 1GB+ offsets, not at offset 0)
            SIZE_MB=\$(blockdev --getsize64 "\$dev" 2>/dev/null | awk '{printf "%d", \$1/1048576}')
            echo "Wiping \$dev (\${SIZE_MB}MB)..."
            dd if=/dev/zero of="\$dev" bs=1M count="\$SIZE_MB" oflag=direct 2>&1
            echo "  Wiped \$dev"
          done
          # Clean rook state directories (both legacy and persistent paths)
          for dir in /var/lib/rook /persistent-rook; do
            if [ -d "\$dir" ]; then
              rm -rf "\$dir"/*
              echo "Cleaned \$dir"
            fi
          done
          echo "=== Done ==="
        volumeMounts:
        - name: rook-data
          mountPath: /var/lib/rook
        - name: rook-persistent
          mountPath: /persistent-rook
        - name: dev
          mountPath: /dev
      volumes:
      - name: rook-data
        hostPath:
          path: /var/lib/rook
      - name: rook-persistent
        hostPath:
          path: /tmp/hostpath_pv/rook
      - name: dev
        hostPath:
          path: /dev
      nodeSelector:
        kubernetes.io/hostname: ${node}
EOF
done

# Wait for cleanup jobs to complete
print_info "  Waiting for cleanup jobs to complete..."
for node in $(kubectl get nodes -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
    kubectl -n default wait --for=condition=complete job/ceph-cleanup-${node} --timeout=60s 2>/dev/null || true
done

# Show cleanup job logs
for node in $(kubectl get nodes -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
    print_info "  [$node]:"
    kubectl -n default logs job/ceph-cleanup-${node} 2>/dev/null | sed 's/^/    /'
done

# Delete cleanup jobs
for node in $(kubectl get nodes -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
    kubectl -n default delete job/ceph-cleanup-${node} 2>/dev/null || true
done

print_success "Rook-Ceph completely removed (including disk data)."
print_info "To redeploy: ./components/ceph/scripts/build.sh"
