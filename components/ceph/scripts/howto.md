# Ceph Storage Build Guide

To deploy Ceph in this playground environment (Minikube + Hyper-V), run the following scripts in order:

## 1. Deploy the Rook Operator
This installs the Helm chart that manages the Ceph cluster, registers CRDs, and starts CSI drivers.
```bash
./components/ceph/scripts/build.sh
```

## 2. Create the Ceph Cluster
This provision the actual storage daemons (MON, MGR, OSD, RGW) using the static manifests.
```bash
./components/ceph/scripts/create-cluster.sh
```

## 3. Verify Health
Wait for all pods to be `Running` in the `rook-ceph` namespace:
```bash
./components/ceph/scripts/status.sh
```

## 4. Troubleshooting
If OSDs fail to start, ensure you have raw disks attached to `minikube-m02` and `minikube-m03`. If previously used, wipe the disks:
```bash
./components/ceph/scripts/destroy.sh cluster
```

Refer to the root [README.md](../README.md) for full architecture and S3 usage.
