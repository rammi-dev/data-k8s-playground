#!/bin/bash
# Surgical cleanup execution for Minikube remnants
# Targets ONLY the "minikube" profile. PRESERVES "zeropod-poc" and cache.

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}  SURGICAL MINIKUBE CLEANUP (WSL)${NC}"
echo -e "${CYAN}============================================${NC}"

# Confirm with user
read -p "This will surgically remove only 'minikube' remnants. Continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Aborted.${NC}"
    exit 1
fi

# 1. Surgical Kubeconfig Cleanup
echo -e "\n${YELLOW}[1] Cleaning up ~/.kube/config...${NC}"
if [ -f ~/.kube/config ]; then
    echo -e "${CYAN}  Removing 'minikube' context...${NC}"
    kubectl config unset contexts.minikube
    echo -e "${CYAN}  Removing 'minikube' cluster...${NC}"
    kubectl config unset clusters.minikube
    echo -e "${CYAN}  Removing 'minikube' user...${NC}"
    kubectl config unset users.minikube
    echo -e "${GREEN}[DONE] Kubeconfig cleanup complete.${NC}"
else
    echo -e "${GREEN}[SKIP] ~/.kube/config not found${NC}"
fi

# 2. Surgical Machine Directory Cleanup (Windows side)
WIN_MINIKUBE_DIR="/mnt/c/Users/kryst/.minikube"
echo -e "\n${YELLOW}[2] Cleaning up targeted machine folders in Windows...${NC}"
if [ -d "$WIN_MINIKUBE_DIR/machines" ]; then
    # Targeted machines (explicit list to be safe)
    TARGETS=("minikube" "minikube-m02" "minikube-m03")
    
    for m in "${TARGETS[@]}"; do
        TARGET_PATH="$WIN_MINIKUBE_DIR/machines/$m"
        if [ -d "$TARGET_PATH" ]; then
            echo -e "${CYAN}  Attempting to delete: $m...${NC}"
            rm -rf "$TARGET_PATH"
            if [ -d "$TARGET_PATH" ]; then
                echo -e "${RED}[WARNING] $m could not be fully deleted (likely locked VHDX files).${NC}"
                echo -e "${RED}          Restarting your machine or stopping Hyper-V may help.${NC}"
            else
                echo -e "${GREEN}[DONE] Deleted $m folder successfully.${NC}"
            fi
        fi
    done
    
    # Check if we can delete the base directory if it's mostly empty (but keep machines)
    if [ -d "$WIN_MINIKUBE_DIR" ]; then
        echo -e "${CYAN}  Cleaning small metadata folders (leaving 'machines' and your preserved profiles)...${NC}"
        # Only delete folders we know are safe metadata folders
        # DO NOT delete cache, files, or machines (machines contains zeropod-poc)
        for dir in "addons" "certs" "config" "logs"; do
            DIR_PATH="$WIN_MINIKUBE_DIR/$dir"
            if [ -d "$DIR_PATH" ]; then
                echo -e "    Removing $dir..."
                rm -rf "$DIR_PATH"
            fi
        done
        echo -e "${GREEN}[DONE] Metadata cleanup complete.${NC}"
    fi
else
    echo -e "${GREEN}[SKIP] Windows machine directory not found.${NC}"
fi

# 3. Environment Variables
echo -e "\n${YELLOW}[3] Suggestions for environment variables...${NC}"
echo -e "${CYAN}If you have MINIKUBE_* variables in your ~/.bashrc or ~/.zshrc, consider removing them.${NC}"
echo -e "${CYAN}Current session cleanup:${NC}"
echo "unset MINIKUBE_ACTIVE_DOCKERD"
echo "unset MINIKUBE_HOME"

echo -e "\n${CYAN}============================================${NC}"
echo -e "${GREEN}  Surgical cleanup complete.${NC}"
echo -e "${CYAN}============================================${NC}"
echo -e "Run ./cleanup-check.sh again to verify the final state."
