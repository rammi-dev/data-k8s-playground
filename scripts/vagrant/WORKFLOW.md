# Vagrant Workflows

Daily patterns for working with the VM.

## First Time Setup

```bash
# 1. Create VM with full provisioning (~10 min)
./vagrant.sh build

# 2. SSH into VM
./vagrant.sh ssh

# 3. Start minikube
cd /vagrant && ./scripts/minikube/build.sh

# 4. (Optional) Save as custom box for faster rebuilds
exit
./vagrant.sh package my-platform
```

## Daily Work

### Morning Start (after stop)
```bash
./vagrant.sh start           # ~30-60 seconds
./vagrant.sh ssh
cd /vagrant
./scripts/minikube/build.sh  # Start minikube
```

### Morning Start (after suspend)
```bash
./vagrant.sh resume          # ~5 seconds
./vagrant.sh ssh
# Minikube already running!
```

### End of Day
```bash
exit                         # Leave SSH
./vagrant.sh stop            # Graceful shutdown
```

## Quick Breaks

### Lunch / Meeting
```bash
exit
./vagrant.sh suspend         # Save state to disk
```

### Back from Break
```bash
./vagrant.sh resume          # Instant restore
./vagrant.sh ssh
# Everything exactly as you left it
```

## Weekly Maintenance

### Create Checkpoint Before Updates
```bash
./vagrant.sh snapshot save before-weekly-update
# ... do updates ...
# If something breaks:
./vagrant.sh snapshot restore before-weekly-update
```

### Clean Up Old Snapshots
```bash
./vagrant.sh snapshot list
./vagrant.sh snapshot delete old-snapshot-name
```

## Fresh Start

### Keep Custom Box
```bash
./vagrant.sh destroy data-playground
./vagrant.sh build --box my-platform  # Instant, no provisioning
```

### Full Clean Rebuild
```bash
./vagrant.sh destroy data-playground
./vagrant.sh build                    # Full provisioning
```

## Workflow Comparison

| Scenario | Commands | Time |
|----------|----------|------|
| First build | `build` | ~10 min |
| Build from custom box | `build --box name` | ~1 min |
| Start after stop | `start` + minikube | ~2 min |
| Resume after suspend | `resume` | ~10 sec |
| Quick break | `suspend` → `resume` | instant |

## Recommended Daily Pattern

```
┌─────────────────────────────────────────────────────────┐
│  MORNING                                                │
│  ├─ After stop:  start → ssh → minikube build          │
│  └─ After suspend: resume → ssh (minikube running)     │
├─────────────────────────────────────────────────────────┤
│  DURING DAY                                             │
│  ├─ Work: ssh                                           │
│  ├─ Quick break: suspend                                │
│  └─ Back: resume → ssh                                  │
├─────────────────────────────────────────────────────────┤
│  EVENING                                                │
│  └─ stop                                                │
└─────────────────────────────────────────────────────────┘
```

## State Diagram

```
                    ┌──────────┐
                    │ No VM    │
                    └────┬─────┘
                         │ build
                         ▼
    ┌───────────────────────────────────────┐
    │              RUNNING                   │
    │  (minikube, docker, services active)  │
    └───┬─────────┬─────────────┬───────────┘
        │         │             │
   stop │    suspend       destroy
        │         │             │
        ▼         ▼             ▼
   ┌─────────┐ ┌───────────┐ ┌──────────┐
   │ STOPPED │ │ SUSPENDED │ │ DESTROYED│
   │         │ │           │ │          │
   │ Clean   │ │ State on  │ │ VM gone  │
   │ shutdown│ │ disk      │ │ Box kept │
   └────┬────┘ └─────┬─────┘ └──────────┘
        │            │
   start│       resume
        │            │
        └──────┬─────┘
               ▼
          ┌─────────┐
          │ RUNNING │
          └─────────┘
```

## Tips

1. **Use suspend for breaks** - Much faster than stop/start
2. **Stop before sleep/shutdown** - Suspend can corrupt if host loses power
3. **Create custom box after provisioning** - Saves 10 min on rebuilds
4. **Snapshot before experiments** - Easy rollback if things break
5. **Weekly stop** - Clears any accumulated state issues
