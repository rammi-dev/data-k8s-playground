# Data Infrastructure Playground

A modular infrastructure playground for testing data components (Ceph, etc.) using Vagrant and minikube.

## Prerequisites

### Windows Host

1. **VirtualBox** (6.1+)
   - Download: https://www.virtualbox.org/wiki/Downloads
   - Install with default settings

2. **Vagrant** (2.3+)
   - Download: https://www.vagrantup.com/downloads
   - Install the Windows version (not WSL version)
   - Verify: Open PowerShell and run `vagrant --version`

3. **WSL2** (Ubuntu recommended)
   - The scripts are designed to run from WSL
   - WSL calls `vagrant.exe` on Windows with automatic path translation

### Project Location Requirement

**Important:** This project must be located on the Windows filesystem (DrvFs), not the WSL filesystem.

```bash
# Correct locations (Windows filesystem via WSL):
/mnt/c/Work/playground
/mnt/d/projects/playground

# Incorrect locations (WSL filesystem - will NOT work):
/home/user/playground
~/projects/playground
```

This is required because Vagrant shared folders only work with DrvFs paths when running from WSL.

### Verify Installation

From WSL terminal:
```bash
# Should find Windows Vagrant
vagrant.exe --version

# Should find VirtualBox
VBoxManage.exe --version
```

## Quick Start

### 1. Configure

Edit `config.yaml` to set your project path and customize resources:

```yaml
paths:
  # REQUIRED: Set this to where you cloned the project
  host_project_path: "/mnt/c/Work/playground"
  host_data_path: "/mnt/c/Work/playground-data"

vm:
  cpus: 4
  memory: 8192    # MB

minikube:
  nodes: 1
  cpus: 3
  memory: 6144    # MB
```

### 2. Create VM

```bash
./scripts/vagrant/build.sh
```

This provisions an Ubuntu VM with Docker, minikube, Helm, and kubectl.

### 3. SSH into VM

```bash
./scripts/vagrant/ssh.sh
```

### 4. Start Minikube (inside VM)

```bash
cd /vagrant
./scripts/minikube/build.sh
```

### 5. Deploy Components (inside VM)

```bash
# Enable component in config.yaml first
./components/ceph/scripts/build.sh
```

## Project Structure

```
playground/
├── config.yaml              # Central configuration
├── Vagrantfile              # VM provisioning
├── scripts/
│   ├── common/              # Shared utilities
│   ├── vagrant/             # VM management (run from WSL)
│   │   ├── build.sh         # Create VM
│   │   ├── destroy.sh       # Delete VM
│   │   ├── start.sh         # Start VM
│   │   ├── stop.sh          # Stop VM
│   │   ├── ssh.sh           # SSH into VM
│   │   └── status.sh        # Check VM status
│   └── minikube/            # Cluster management (run inside VM)
│       ├── build.sh         # Start cluster
│       ├── destroy.sh       # Delete cluster
│       └── status.sh        # Check status
├── components/
│   └── <component>/
│       ├── README.md        # Component documentation
│       ├── scripts/
│       │   ├── build.sh     # Deploy component
│       │   └── destroy.sh   # Remove component
│       └── helm/
│           └── values.yaml  # Helm overrides
├── docs/
│   └── NETWORKING.md        # Network access from Windows host
└── data/                    # Persistent storage (synced to host)
```

## VM Management

### Commands

| Command | Description |
|---------|-------------|
| `./scripts/vagrant/build.sh` | Create and provision VM |
| `./scripts/vagrant/start.sh` | Start existing VM |
| `./scripts/vagrant/stop.sh` | Stop VM (graceful) |
| `./scripts/vagrant/destroy.sh` | Delete VM completely |
| `./scripts/vagrant/ssh.sh` | SSH into VM |
| `./scripts/vagrant/status.sh` | Check VM status and health |

### VM Lifecycle Procedures

#### First-time Setup
```bash
# 1. Configure paths and resources in config.yaml
# 2. Build the VM (includes provisioning)
./scripts/vagrant/build.sh

# 3. SSH into VM and start minikube
./scripts/vagrant/ssh.sh
cd /vagrant && ./scripts/minikube/build.sh
```

#### Daily Usage
```bash
# Start VM (if stopped)
./scripts/vagrant/start.sh

# Check status
./scripts/vagrant/status.sh

# SSH into VM
./scripts/vagrant/ssh.sh

# Stop VM when done
./scripts/vagrant/stop.sh
```

#### Clean Rebuild
```bash
# Destroy existing VM
./scripts/vagrant/destroy.sh

# Clean VirtualBox leftovers (if needed)
rm -rf .vagrant
VBoxManage.exe unregistervm "data-playground" --delete 2>/dev/null

# Rebuild from scratch
./scripts/vagrant/build.sh
```

#### Re-provision (update VM software)
```bash
# From WSL, re-run provisioning without destroying VM
cd /mnt/c/Work/playground
vagrant.exe provision
```

### VM Credentials

| Item | Value |
|------|-------|
| Username | `vagrant` |
| Password | `vagrant` |
| SSH | `./scripts/vagrant/ssh.sh` or `vagrant.exe ssh` |
| Sudo | No password required |

## Persistent Data

Data is persisted to the host at the path configured in `config.yaml`:

```yaml
paths:
  host_data_path: "/mnt/c/playground-data"
```

This directory is mounted inside the VM at `/data`.

## Adding New Components

1. Create component directory:
   ```
   components/<name>/
   ├── README.md
   ├── scripts/
   │   ├── build.sh
   │   └── destroy.sh
   └── helm/
       └── values.yaml
   ```

2. Add configuration to `config.yaml`:
   ```yaml
   components:
     <name>:
       enabled: false
       namespace: "<name>"
       chart_repo: "https://..."
       chart_name: "<chart>"
       chart_version: "x.y.z"
   ```

3. Update `scripts/common/config-loader.sh` to load the new component config.

## Documentation

| Guide | Description |
|-------|-------------|
| [Networking](docs/NETWORKING.md) | Access K8s services from Windows host |
| [Minikube Scripts](scripts/minikube/README.md) | Minikube management and addons |
| [Monitoring](components/monitoring/README.md) | Grafana, Prometheus, Loki stack |
| [Ceph](components/ceph/README.md) | Ceph storage deployment |

## Troubleshooting

### "Host path of the shared folder is not supported from WSL"

This error occurs when the `host_project_path` in `config.yaml` doesn't match the actual project location.

**Solution:** Update `paths.host_project_path` in `config.yaml`:

```yaml
paths:
  host_project_path: "/mnt/c/Work/playground"  # Must match your actual project location
```

### Vagrant not found from WSL

Ensure Windows Vagrant is in PATH. Add to `~/.bashrc`:
```bash
export PATH="$PATH:/mnt/c/HashiCorp/Vagrant/bin"
```

### VirtualBox networking issues

If VM networking fails, try:
```bash
./scripts/vagrant/destroy.sh
./scripts/vagrant/build.sh
```

### Minikube won't start

Check Docker is running inside VM:
```bash
sudo systemctl status docker
```
