#!/bin/bash
# Surgical cleanup check for Minikube remnants

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}  MINIKUBE CLEANUP VERIFICATION (WSL)${NC}"
echo -e "${CYAN}============================================${NC}"

# 1. WSL Kubeconfig
echo -e "\n${YELLOW}[1] Checking WSL kubeconfig...${NC}"
if [ -f ~/.kube/config ]; then
    CONTEXTS=$(kubectl config get-contexts -o name 2>/dev/null | grep -E "^minikube$")
    if [ ! -z "$CONTEXTS" ]; then
        echo -e "${RED}[FOUND] Minikube context still exists in ~/.kube/config${NC}"
    else
        echo -e "${GREEN}[OK] No minikube context in ~/.kube/config${NC}"
    fi
else
    echo -e "${GREEN}[OK] ~/.kube/config not found${NC}"
fi

# 2. Windows-side Machine Directories (via WSL mount)
WIN_MINIKUBE_DIR="/mnt/c/Users/kryst/.minikube"
echo -e "\n${YELLOW}[2] Checking Windows-side machine folders...${NC}"
if [ -d "$WIN_MINIKUBE_DIR/machines" ]; then
    # Targeted machines
    MINIKUBE_MACHINES=$(ls "$WIN_MINIKUBE_DIR/machines" 2>/dev/null | grep -E "^minikube(-m[0-9]+)?$")
    if [ ! -z "$MINIKUBE_MACHINES" ]; then
        echo -e "${RED}[FOUND] Leftover minikube machines in Windows:${NC}"
        echo "$MINIKUBE_MACHINES" | sed 's/^/  - /'
        
        # Check for VHDX files in these machines
        echo -e "${CYAN}  Checking for orphan VHDX/AVHDX files...${NC}"
        for m in $MINIKUBE_MACHINES; do
            VHDX_FILES=$(find "$WIN_MINIKUBE_DIR/machines/$m" -name "*.vhdx" -o -name "*.avhdx" 2>/dev/null)
            if [ ! -z "$VHDX_FILES" ]; then
                echo -e "${RED}  - $m contains orphan volumes:${NC}"
                echo "$VHDX_FILES" | sed 's/^/    - /'
            fi
        done
    else
        echo -e "${GREEN}[OK] No 'minikube*' machine folders found in Windows.${NC}"
    fi
    
    # Check for preserved machines
    PRESERVED=$(ls "$WIN_MINIKUBE_DIR/machines" 2>/dev/null | grep -E "zeropod-poc")
    if [ ! -z "$PRESERVED" ]; then
        echo -e "${GREEN}[INFO] Preserved machines detected (will NOT be deleted):${NC}"
        echo "$PRESERVED" | sed 's/^/  - /'
    fi
else
    echo -e "${GREEN}[OK] Windows minikube machine directory not found.${NC}"
fi

# 3. WSL Cache
echo -e "\n${YELLOW}[3] Checking WSL minikube cache...${NC}"
if [ -d ~/.minikube/cache ]; then
    CACHE_SIZE=$(du -sh ~/.minikube/cache 2>/dev/null | cut -f1)
    echo -e "${YELLOW}[INFO] WSL minikube cache size: $CACHE_SIZE${NC}"
    echo -e "${CYAN}  (This is shared across profiles and usually kept to avoid re-downloads)${NC}"
else
    echo -e "${GREEN}[OK] WSL cache directory not found.${NC}"
fi

# 4. Environment Variables
echo -e "\n${YELLOW}[4] Checking environment variables...${NC}"
MINIKUBE_VARS=$(env | grep -i "MINIKUBE")
if [ ! -z "$MINIKUBE_VARS" ]; then
    echo -e "${RED}[FOUND] Minikube environment variables:${NC}"
    echo "$MINIKUBE_VARS" | sed 's/^/  - /'
else
    echo -e "${GREEN}[OK] No minikube environment variables found.${NC}"
fi

echo -e "\n${CYAN}============================================${NC}"
echo -e "${CYAN}  Summary: Check complete.${NC}"
echo -e "${CYAN}============================================${NC}"
echo -e "To proceed with surgical cleanup, run: ./cleanup-wsl.sh"
