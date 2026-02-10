#!/bin/bash
# Delete minikube cluster
# Run from WSL

echo "This will delete the entire minikube cluster!"
read -p "Are you sure? (yes/no): " confirm

if [ "$confirm" = "yes" ]; then
    minikube delete --all --purge
    echo "Cluster deleted."
else
    echo "Aborted."
fi
