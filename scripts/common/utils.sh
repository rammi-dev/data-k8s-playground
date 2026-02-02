#!/bin/bash
# Common utility functions for the data playground

# Get the project root directory
get_project_root() {
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    echo "$(cd "$script_dir/../.." && pwd)"
}

# Check if running inside WSL
is_wsl() {
    grep -qi microsoft /proc/version 2>/dev/null
}

# Check if running inside the Vagrant VM
is_vagrant_vm() {
    [[ -d /vagrant ]] && [[ -f /etc/vagrant_provisioned_at ]] || [[ "$(whoami)" == "vagrant" ]]
}

# Convert WSL path to Windows path
# /mnt/c/path -> C:\path
wsl_to_windows_path() {
    local wsl_path="$1"
    if [[ "$wsl_path" =~ ^/mnt/([a-z])/(.*) ]]; then
        local drive="${BASH_REMATCH[1]^^}"
        local rest="${BASH_REMATCH[2]}"
        echo "${drive}:\\${rest//\//\\}"
    else
        echo "$wsl_path"
    fi
}

# Get vagrant executable (vagrant.exe on WSL, vagrant otherwise)
get_vagrant_cmd() {
    if is_wsl; then
        echo "vagrant.exe"
    else
        echo "vagrant"
    fi
}

# Get vagrant directory (where Vagrantfile lives)
get_vagrant_dir() {
    local project_root="$(get_project_root)"
    echo "$project_root/scripts/vagrant"
}

# Run vagrant command with proper path handling
# Uses VAGRANT_FILE env var if set, otherwise default Vagrantfile
run_vagrant() {
    local vagrant_dir="$(get_vagrant_dir)"
    local vagrant_cmd="$(get_vagrant_cmd)"

    if is_wsl; then
        export VAGRANT_WSL_ENABLE_WINDOWS_ACCESS="1"
    fi

    # Use custom Vagrantfile if specified
    if [[ -n "$VAGRANT_FILE" ]]; then
        export VAGRANT_VAGRANTFILE="$VAGRANT_FILE"
    fi

    cd "$vagrant_dir" && $vagrant_cmd "$@"
}

# Print colored output
print_info() {
    echo -e "\033[0;34m[INFO]\033[0m $1"
}

print_success() {
    echo -e "\033[0;32m[SUCCESS]\033[0m $1"
}

print_error() {
    echo -e "\033[0;31m[ERROR]\033[0m $1"
}

print_warning() {
    echo -e "\033[0;33m[WARNING]\033[0m $1"
}

# Check if a command exists
command_exists() {
    command -v "$1" &> /dev/null
}

# Wait for a condition with timeout
wait_for() {
    local description="$1"
    local check_cmd="$2"
    local timeout="${3:-120}"
    local interval="${4:-5}"

    print_info "Waiting for $description (timeout: ${timeout}s)..."
    local elapsed=0
    while ! eval "$check_cmd" &>/dev/null; do
        if [[ $elapsed -ge $timeout ]]; then
            print_error "Timeout waiting for $description"
            return 1
        fi
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    print_success "$description is ready"
}
