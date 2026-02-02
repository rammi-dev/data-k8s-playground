#!/bin/bash
# Vagrant VM Management Script
# Usage: ./vagrant.sh [-f <vagrantfile>] <command> [options]
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common/utils.sh"
source "$SCRIPT_DIR/../common/config-loader.sh"

# Parse global options
while [[ $# -gt 0 ]]; do
    case "$1" in
        -f|--file)
            export VAGRANT_FILE="$2"
            shift 2
            ;;
        *)
            break
            ;;
    esac
done

show_help() {
    local vagrantfile="${VAGRANT_FILE:-Vagrantfile}"
    cat << EOF
Vagrant VM Management - $VM_NAME

Usage: ./vagrant.sh [-f <vagrantfile>] <command> [options]

GLOBAL OPTIONS:
  -f, --file <path>   Use custom Vagrantfile (default: Vagrantfile)

LIFECYCLE COMMANDS:
  build [name]          Create and provision a new VM (default: $VM_NAME)
  start [name|id]       Start VM by name or ID (default: $VM_NAME)
  stop [name|id]        Stop VM by name or ID (default: $VM_NAME)
  restart [name|id]     Restart VM by name or ID (default: $VM_NAME)
  destroy <name|id>     Destroy VM (must specify name or ID)

ACCESS COMMANDS:
  ssh [name|id]         SSH into VM (default: $VM_NAME)
  status [name|id]      Show VM status and details
  list                  List all Vagrant VMs (shows IDs)
  prune                 Remove stale/invalid VM entries from cache

MAINTENANCE COMMANDS:
  provision [name|id]   Re-run provisioning scripts

SNAPSHOT COMMANDS:
  snapshot save [name]      Save current state (default: timestamp)
  snapshot restore <name>   Restore to a saved snapshot
  snapshot list             List all snapshots
  snapshot delete <name>    Delete a snapshot

EXAMPLES:
  ./vagrant.sh build                    # Create VM with default name
  ./vagrant.sh build my-vm              # Create VM with custom name
  ./vagrant.sh -f MyVagrantfile build   # Use custom Vagrantfile
  ./vagrant.sh list                     # List all VMs (shows IDs)
  ./vagrant.sh start                    # Start default VM
  ./vagrant.sh start $VM_NAME           # Start VM by name
  ./vagrant.sh stop $VM_NAME            # Stop VM by name
  ./vagrant.sh destroy 016b4ff          # Destroy VM by ID
  ./vagrant.sh snapshot save before-upgrade

CURRENT VAGRANTFILE: $vagrantfile

CONFIGURATION:
  VM Name:    $VM_NAME
  CPUs:       $VM_CPUS
  Memory:     ${VM_MEMORY}MB
  Box:        $VM_BOX
  Config:     $CONFIG_FILE
EOF
}

cmd_build() {
    local vm_name="${1:-data-playground}"

    print_info "Building Vagrant VM: $vm_name"
    print_info "Configuration: ${VM_CPUS} CPUs, ${VM_MEMORY}MB RAM"

    # Ensure data directory exists
    if [[ ! -d "$HOST_DATA_PATH" ]]; then
        print_info "Creating data directory: $HOST_DATA_PATH"
        mkdir -p "$HOST_DATA_PATH"
    fi

    print_info "Starting Vagrant provisioning..."
    run_vagrant up --provision "$vm_name"

    print_success "VM '$vm_name' is ready!"
    print_info "Next steps:"
    print_info "  1. SSH into VM: ./vagrant.sh ssh $vm_name"
    print_info "  2. Start minikube: cd /vagrant && ./scripts/minikube/build.sh"
}

cmd_start() {
    local vm_name="${1:-data-playground}"

    print_info "Starting Vagrant VM: $vm_name"
    run_vagrant up --no-provision "$vm_name"
    print_success "VM '$vm_name' is running."
    print_info "SSH into VM: ./vagrant.sh ssh $vm_name"
}

cmd_stop() {
    local vm_name="${1:-data-playground}"

    print_info "Stopping Vagrant VM: $vm_name"
    run_vagrant halt "$vm_name"
    print_success "VM '$vm_name' has been stopped."
}

cmd_restart() {
    local vm_name="${1:-data-playground}"

    print_info "Restarting Vagrant VM: $vm_name"
    run_vagrant reload "$vm_name"
    print_success "VM '$vm_name' has been restarted."
}

cmd_destroy() {
    local vm_id="$1"

    if [[ -z "$vm_id" ]]; then
        print_error "Usage: ./vagrant.sh destroy <name|id>"
        print_info "Use './vagrant.sh list' to see VM names and IDs"
        print_info "Example: ./vagrant.sh destroy data-playground"
        print_info "Example: ./vagrant.sh destroy 016b4ff"
        exit 1
    fi

    print_warning "This will destroy VM '$vm_id' and all its data!"
    read -p "Type 'yes' to confirm: " confirm

    if [[ "$confirm" != "yes" ]]; then
        print_info "Aborted."
        exit 0
    fi

    print_info "Destroying Vagrant VM: $vm_id"

    # Try vagrant destroy first
    if ! run_vagrant destroy -f "$vm_id" 2>/dev/null; then
        # If vagrant fails, try direct VirtualBox cleanup (orphaned VM)
        print_warning "Vagrant couldn't find VM, trying VirtualBox directly..."
        local vbox_cmd="VBoxManage"
        is_wsl && vbox_cmd="VBoxManage.exe"

        # Power off if running, then unregister
        $vbox_cmd controlvm "$vm_id" poweroff 2>/dev/null || true
        sleep 1
        if $vbox_cmd unregistervm "$vm_id" --delete 2>/dev/null; then
            print_success "Removed orphaned VirtualBox VM '$vm_id'"
        else
            print_error "Could not find VM '$vm_id' in Vagrant or VirtualBox"
            exit 1
        fi
    fi

    print_success "VM '$vm_id' has been destroyed."
}

cmd_ssh() {
    local vm_name="${1:-data-playground}"

    print_info "Connecting to VM: $vm_name"
    run_vagrant ssh "$vm_name"
}

cmd_status() {
    local vm_name="${1:-data-playground}"

    print_info "Vagrant VM Status: $vm_name"
    echo "=================================="

    echo ""
    print_info "VM State:"
    run_vagrant status "$vm_name"

    # If VM is running, get more details
    if run_vagrant status "$vm_name" 2>/dev/null | grep -q "running"; then
        echo ""
        print_info "VM Configuration:"
        echo "  CPUs: $VM_CPUS"
        echo "  Memory: $VM_MEMORY MB"
        echo "  Box: $VM_BOX"

        echo ""
        print_info "Network Info:"
        run_vagrant ssh "$vm_name" -c "hostname -I" 2>/dev/null || echo "  Could not retrieve network info"

        echo ""
        print_info "Disk Usage:"
        run_vagrant ssh "$vm_name" -c "df -h / /vagrant /data 2>/dev/null" 2>/dev/null || echo "  Could not retrieve disk info"

        echo ""
        print_info "Docker Status:"
        run_vagrant ssh "$vm_name" -c "docker info 2>/dev/null | head -5" 2>/dev/null || echo "  Docker not running"

        echo ""
        print_info "Minikube Status:"
        run_vagrant ssh "$vm_name" -c "minikube status 2>/dev/null" 2>/dev/null || echo "  Minikube not running"
    fi
}

cmd_list() {
    print_info "All Vagrant VMs:"
    run_vagrant global-status
}

cmd_prune() {
    print_info "Pruning stale VM entries..."
    run_vagrant global-status --prune
    print_success "Stale entries removed."
}

cmd_provision() {
    local vm_name="${1:-data-playground}"

    print_info "Re-provisioning Vagrant VM: $vm_name"
    print_info "This will re-run the provisioning scripts..."
    run_vagrant provision "$vm_name"
    print_success "VM '$vm_name' has been re-provisioned."
}

cmd_snapshot() {
    local subcmd="${1:-}"
    shift || true

    case "$subcmd" in
        save)
            local name="${1:-$(date +%Y%m%d-%H%M%S)}"
            print_info "Saving snapshot '$name' for VM: $VM_NAME"
            run_vagrant snapshot save "$name"
            print_success "Snapshot '$name' saved."
            ;;
        restore)
            local name="$1"
            if [[ -z "$name" ]]; then
                print_error "Usage: ./vagrant.sh snapshot restore <name>"
                exit 1
            fi
            print_warning "This will restore VM to snapshot '$name'. Changes since will be lost!"
            read -p "Are you sure? (y/N): " confirm
            if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
                print_info "Aborted."
                exit 0
            fi
            print_info "Restoring snapshot '$name'..."
            run_vagrant snapshot restore "$name"
            print_success "Snapshot '$name' restored."
            ;;
        list)
            print_info "Snapshots for VM: $VM_NAME"
            run_vagrant snapshot list
            ;;
        delete)
            local name="$1"
            if [[ -z "$name" ]]; then
                print_error "Usage: ./vagrant.sh snapshot delete <name>"
                exit 1
            fi
            print_warning "This will permanently delete snapshot '$name'"
            read -p "Are you sure? (y/N): " confirm
            if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
                print_info "Aborted."
                exit 0
            fi
            run_vagrant snapshot delete "$name"
            print_success "Snapshot '$name' deleted."
            ;;
        *)
            print_error "Unknown snapshot command: $subcmd"
            echo "Usage: ./vagrant.sh snapshot <save|restore|list|delete> [name]"
            exit 1
            ;;
    esac
}

# Main command dispatcher
COMMAND="${1:-help}"
shift || true

case "$COMMAND" in
    build)      cmd_build "$@" ;;
    start)      cmd_start "$@" ;;
    stop)       cmd_stop "$@" ;;
    restart)    cmd_restart "$@" ;;
    destroy)    cmd_destroy "$@" ;;
    ssh)        cmd_ssh "$@" ;;
    status)     cmd_status "$@" ;;
    list)       cmd_list ;;
    prune)      cmd_prune ;;
    provision)  cmd_provision "$@" ;;
    snapshot)   cmd_snapshot "$@" ;;
    help|--help|-h)
        show_help
        ;;
    *)
        print_error "Unknown command: $COMMAND"
        echo ""
        show_help
        exit 1
        ;;
esac
