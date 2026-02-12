#!/bin/bash
# Remove Rook-Ceph components
#
# Usage:
#   destroy.sh cluster   — Remove cluster CRDs, wipe disks (keeps operator)
#   destroy.sh operator  — Uninstall operator Helm release, delete CRDs, namespace
#   destroy.sh all       — Both: cluster + operator (full teardown)
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

source "$PROJECT_ROOT/scripts/common/utils.sh"
source "$PROJECT_ROOT/scripts/common/config-loader.sh"

MODE="${1:-}"
if [[ "$MODE" != "cluster" && "$MODE" != "operator" && "$MODE" != "all" ]]; then
    echo "Usage: $0 {cluster|operator|all}"
    echo ""
    echo "  cluster   — Remove cluster CRDs, wipe disks (keeps operator)"
    echo "  operator  — Uninstall operator Helm release, delete CRDs, namespace"
    echo "  all       — Full teardown (cluster + operator)"
    exit 1
fi

if ! kubectl cluster-info &>/dev/null; then
    print_error "Kubernetes cluster is not accessible"
    exit 1
fi

# Helper: remove finalizers from all objects of a given CRD
remove_finalizers() {
    local crd="$1"
    for obj in $(kubectl -n "$CEPH_NAMESPACE" get "$crd" -o name 2>/dev/null); do
        kubectl -n "$CEPH_NAMESPACE" patch "$obj" --type merge -p '{"metadata":{"finalizers":null}}' 2>/dev/null || true
    done
}

# ============================================================================
# DESTROY CLUSTER
# ============================================================================
destroy_cluster() {
    print_warning "Destroying Ceph cluster (CRDs + disk data)..."
    read -p "Are you sure? (y/N): " confirm
    [[ "$confirm" != "y" && "$confirm" != "Y" ]] && { print_info "Aborted."; exit 0; }

    # Scale down operator to prevent recreation during cleanup
    print_info "Step 1: Scaling down operator..."
    kubectl -n "$CEPH_NAMESPACE" scale deploy/rook-ceph-operator --replicas=0 2>/dev/null || true
    kubectl -n "$CEPH_NAMESPACE" wait --for=delete pod -l app=rook-ceph-operator --timeout=60s 2>/dev/null || true

    # Uninstall cluster Helm release if present (legacy: old build.sh used Helm for cluster)
    if helm status rook-ceph-cluster -n "$CEPH_NAMESPACE" &>/dev/null; then
        print_info "  Uninstalling legacy rook-ceph-cluster Helm release..."
        timeout 60 helm uninstall rook-ceph-cluster -n "$CEPH_NAMESPACE" --no-hooks 2>/dev/null &
        HELM_PID=$!
        sleep 5
        # Remove finalizers while helm uninstall runs (may block on them)
        for crd in $(kubectl get crd -o name 2>/dev/null | grep -E 'ceph\.rook\.io|csi\.ceph\.io|objectbucket\.io'); do
            remove_finalizers "$(basename "$crd")"
        done
        wait $HELM_PID 2>/dev/null || true
        print_success "  Legacy cluster Helm release uninstalled"
    fi

    # Remove finalizers from Ceph CRD objects
    print_info "Step 2: Removing finalizers..."
    for crd in $(kubectl get crd -o name 2>/dev/null | grep -E 'ceph\.rook\.io|csi\.ceph\.io|objectbucket\.io'); do
        remove_finalizers "$(basename "$crd")"
    done

    # Delete Ceph CRD objects
    print_info "Step 3: Deleting Ceph resources..."
    for crd in $(kubectl get crd -o name 2>/dev/null | grep -E 'ceph\.rook\.io|csi\.ceph\.io|objectbucket\.io'); do
        kubectl -n "$CEPH_NAMESPACE" delete "$(basename "$crd")" --all --timeout=30s 2>/dev/null || true
    done

    # Delete PVCs and StorageClasses
    print_info "Step 4: Deleting PVCs and StorageClasses..."
    kubectl -n "$CEPH_NAMESPACE" delete pvc --all --timeout=30s 2>/dev/null || true
    kubectl delete storageclass ceph-block ceph-filesystem ceph-bucket 2>/dev/null || true

    # Delete operator-managed state
    print_info "Step 5: Deleting operator-managed state..."
    for obj in secret/rook-ceph-mon secret/rook-ceph-config \
               cm/rook-ceph-mon-endpoints cm/rook-ceph-csi-config \
               cm/rook-ceph-csi-mapping-config cm/rook-ceph-pdbstatemap; do
        kubectl -n "$CEPH_NAMESPACE" patch "$obj" --type merge -p '{"metadata":{"finalizers":null}}' 2>/dev/null || true
        kubectl -n "$CEPH_NAMESPACE" delete "$obj" --timeout=10s 2>/dev/null || true
    done

    # Zap disks
    print_info "Step 6: Zapping disks on all nodes..."
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
            MOUNTS=\$(lsblk -n -o MOUNTPOINT "\$dev" 2>/dev/null | grep -c '/' || true)
            if [ "\$MOUNTS" -gt 0 ]; then
              echo "Skipping \$dev (has mounted partitions)"
              continue
            fi
            SIZE_MB=\$(blockdev --getsize64 "\$dev" 2>/dev/null | awk '{printf "%d", \$1/1048576}')
            echo "Wiping \$dev (\${SIZE_MB}MB)..."
            dd if=/dev/zero of="\$dev" bs=1M count="\$SIZE_MB" oflag=direct 2>&1
            echo "  Wiped \$dev"
          done
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

    # Wait for cleanup jobs
    print_info "  Waiting for cleanup jobs..."
    for node in $(kubectl get nodes -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
        kubectl -n default wait --for=condition=complete job/ceph-cleanup-${node} --timeout=60s 2>/dev/null || true
    done
    for node in $(kubectl get nodes -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
        print_info "  [$node]:"
        kubectl -n default logs job/ceph-cleanup-${node} 2>/dev/null | sed 's/^/    /'
        kubectl -n default delete job/ceph-cleanup-${node} 2>/dev/null || true
    done

    # Scale operator back up
    kubectl -n "$CEPH_NAMESPACE" scale deploy/rook-ceph-operator --replicas=1 2>/dev/null || true

    print_success "Ceph cluster destroyed (operator still running)"
}

# ============================================================================
# DESTROY OPERATOR
# ============================================================================
destroy_operator() {
    print_warning "Destroying Rook operator (Helm release + CRDs + namespace)..."
    read -p "Are you sure? (y/N): " confirm
    [[ "$confirm" != "y" && "$confirm" != "Y" ]] && { print_info "Aborted."; exit 0; }

    # Uninstall operator Helm release
    print_info "Step 1: Uninstalling operator Helm release..."
    if helm status rook-ceph-operator -n "$CEPH_NAMESPACE" &>/dev/null; then
        helm uninstall rook-ceph-operator -n "$CEPH_NAMESPACE" --timeout=60s 2>/dev/null || true
        print_success "  Operator chart uninstalled"
    else
        print_info "  Operator chart not installed, skipping"
    fi

    # Delete CRDs
    print_info "Step 2: Deleting Ceph CRDs..."
    for crd in $(kubectl get crd -o name 2>/dev/null | grep -E 'ceph\.rook\.io|csi\.ceph\.io|objectbucket\.io'); do
        kubectl delete "$crd" --timeout=30s 2>/dev/null || true
    done

    # Delete namespace
    print_info "Step 3: Deleting namespace..."
    if kubectl get namespace "$CEPH_NAMESPACE" &>/dev/null; then
        kubectl delete namespace "$CEPH_NAMESPACE" --timeout=60s 2>/dev/null || {
            print_warning "  Namespace stuck in Terminating, removing finalizer..."
            kubectl get namespace "$CEPH_NAMESPACE" -o json \
                | python3 -c 'import sys,json; ns=json.load(sys.stdin); ns["spec"]["finalizers"]=[]; json.dump(ns,sys.stdout)' \
                | kubectl replace --raw "/api/v1/namespaces/$CEPH_NAMESPACE/finalize" -f - 2>/dev/null || true
            for i in $(seq 1 12); do
                kubectl get namespace "$CEPH_NAMESPACE" &>/dev/null || break
                sleep 5
            done
        }
        print_success "  Namespace deleted"
    else
        print_info "  Namespace not found, skipping"
    fi

    print_success "Rook operator destroyed"
}

# ============================================================================
# EXECUTE
# ============================================================================
case "$MODE" in
    cluster)
        destroy_cluster
        ;;
    operator)
        destroy_operator
        ;;
    all)
        destroy_cluster
        destroy_operator
        print_success "Rook-Ceph completely removed."
        print_info "To redeploy: ./components/ceph/scripts/build.sh"
        ;;
esac
