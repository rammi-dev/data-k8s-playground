# Vagrant VM Management

Manage VirtualBox VMs for the data infrastructure playground.

See [WORKFLOW.md](WORKFLOW.md) for daily usage patterns.

## Quick Start

```bash
./vagrant.sh build    # Create VM
./vagrant.sh ssh      # Connect
```

## Command Reference

### Lifecycle Commands

#### build
Create a new VM from scratch.

```bash
./vagrant.sh build                    # Base box + provisioning
./vagrant.sh build --box my-platform  # Custom box, no provisioning
```

| Option | Description |
|--------|-------------|
| (none) | Use base box, run full provisioning |
| `--box <name>` | Use custom box, skip provisioning |

---

#### start
Boot a stopped VM.

```bash
./vagrant.sh start
```

- Full OS boot sequence
- Services start fresh
- Minikube needs manual start
- **Duration:** ~30-60 seconds

---

#### stop
Graceful shutdown.

```bash
./vagrant.sh stop
```

- Sends shutdown signal
- RAM freed
- No disk space for state

---

#### suspend
Freeze VM state to disk.

```bash
./vagrant.sh suspend
```

- RAM saved to disk (~40GB)
- Exact state preserved
- **Duration:** ~10-30 seconds

---

#### resume
Restore from suspended state.

```bash
./vagrant.sh resume
```

- RAM restored from disk
- Continues where left off
- **Duration:** ~5-10 seconds

---

#### restart
Stop and start VM.

```bash
./vagrant.sh restart
```

- Applies config changes (CPU, memory)

---

#### destroy
Delete VM completely.

```bash
./vagrant.sh destroy data-playground
```

- VM and disk deleted
- Base boxes preserved
- Custom boxes preserved

---

### Access Commands

#### ssh
Connect to VM.

```bash
./vagrant.sh ssh
```

---

#### status
Show VM details.

```bash
./vagrant.sh status
```

---

#### list
List all Vagrant VMs.

```bash
./vagrant.sh list
```

---

#### prune
Remove stale entries.

```bash
./vagrant.sh prune
```

---

### Snapshot Commands

```bash
./vagrant.sh snapshot save <name>     # Save state
./vagrant.sh snapshot list            # List snapshots
./vagrant.sh snapshot restore <name>  # Restore state
./vagrant.sh snapshot delete <name>   # Delete snapshot
```

---

### Box Commands

#### package
Create custom box from current VM.

```bash
./vagrant.sh package my-platform
```

---

#### box list
List cached boxes.

```bash
./vagrant.sh box list
```

---

#### box remove
Remove a cached box.

```bash
./vagrant.sh box remove my-old-box
```

---

## stop vs suspend

| | stop | suspend |
|---|------|---------|
| Resume time | ~30-60s | ~5-10s |
| Disk usage | None | ~RAM size |
| RAM freed | Yes | No |
| Minikube | Restart needed | Still running |
| Best for | End of day | Quick breaks |

## Configuration

Edit `config.yaml`:

```yaml
vm:
  cpus: 12              # CPU cores
  memory: 40960         # RAM in MB
  disk_size: 50         # Disk in GB
  box: "ubuntu/jammy64" # Base box
  gui: true             # Show window
```

## Troubleshooting

### VM Won't Start
```bash
./vagrant.sh prune
./vagrant.sh destroy data-playground
./vagrant.sh build
```

### VM Hangs
```bash
# Windows PowerShell
VBoxManage controlvm "data-playground" poweroff

# Then
./vagrant.sh start
```

### Config Not Applied
```bash
./vagrant.sh restart
```
