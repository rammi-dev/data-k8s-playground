# Network Access Guide

How to access services running in Kubernetes (inside minikube, inside the VM) from your Windows host.

## Network Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│ Windows Host                                                     │
│                                                                  │
│   Browser/curl ──► localhost:3000                               │
│                         │                                        │
│                         │ VirtualBox Port Forward                │
│                         ▼                                        │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │ Vagrant VM (Ubuntu)                     192.168.56.x    │   │
│   │                                                          │   │
│   │   kubectl port-forward --address 0.0.0.0 ...            │   │
│   │                         │                                │   │
│   │                         ▼                                │   │
│   │   ┌─────────────────────────────────────────────────┐   │   │
│   │   │ Minikube (Docker)                               │   │   │
│   │   │                                                  │   │   │
│   │   │   ┌──────────────────────────────────────────┐  │   │   │
│   │   │   │ Kubernetes Services                      │  │   │   │
│   │   │   │  - Grafana (port 80)                     │  │   │   │
│   │   │   │  - Prometheus (port 9090)                │  │   │   │
│   │   │   │  - Your Apps                             │  │   │   │
│   │   │   └──────────────────────────────────────────┘  │   │   │
│   │   └─────────────────────────────────────────────────┘   │   │
│   └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

## Access Methods

### Method 1: Port Forwarding (Recommended)

Use `kubectl port-forward` with `--address 0.0.0.0` to expose services on the VM's network interface.

```bash
# Inside the VM
kubectl port-forward --address 0.0.0.0 svc/my-service 8080:80 -n my-namespace
```

Then access from Windows using the VM's private network IP:
```
http://192.168.56.x:8080
```

**Get the VM's IP address:**
```bash
# Inside the VM
hostname -I | awk '{print $2}'
```

The second IP is typically the VirtualBox private network IP (192.168.56.x).

### Method 2: VirtualBox Port Forwards

Pre-configure port forwards in the Vagrantfile for frequently used services:

```ruby
# In Vagrantfile
config.vm.network "forwarded_port", guest: 3000, host: 3000  # Grafana
config.vm.network "forwarded_port", guest: 9090, host: 9090  # Prometheus
config.vm.network "forwarded_port", guest: 8080, host: 8080  # General use
```

Then access directly via localhost:
```
http://localhost:3000
```

**Note:** This requires the port-forward to be running inside the VM first.

### Method 3: NodePort Services

Expose services as NodePort to access them directly on the minikube node:

```bash
# Get minikube IP (inside VM)
minikube ip

# Create NodePort service
kubectl expose deployment my-app --type=NodePort --port=80
kubectl get svc my-app  # Note the NodePort (30000-32767)
```

Access via minikube IP from inside the VM, then port-forward that.

### Method 4: Ingress

For HTTP services, use the ingress controller:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app
spec:
  rules:
  - host: my-app.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: my-app
            port:
              number: 80
```

Add to Windows hosts file (`C:\Windows\System32\drivers\etc\hosts`):
```
192.168.56.x my-app.local
```

## Pre-configured Access Scripts

| Service | Script | Default Port |
|---------|--------|--------------|
| Grafana | `components/monitoring/scripts/access-grafana.sh` | 3000 |
| K8s Dashboard | `scripts/minikube/access-dashboard.sh` | (auto) |

### Accessing Grafana from Windows

1. SSH into the VM:
   ```bash
   cd scripts/vagrant && ./vagrant.sh ssh
   ```

2. Run the access script (modify for external access):
   ```bash
   kubectl port-forward --address 0.0.0.0 -n monitoring svc/loki-grafana 3000:80
   ```

3. Open in Windows browser:
   ```
   http://<VM-IP>:3000
   ```

4. Get credentials:
   ```bash
   # Username: admin
   # Password:
   kubectl get secret -n monitoring loki-grafana -o jsonpath="{.data.admin-password}" | base64 -d
   ```

## Troubleshooting

### Can't connect from Windows

1. **Check VM is running:**
   ```bash
   cd scripts/vagrant && ./vagrant.sh status
   ```

2. **Check port-forward is running:**
   ```bash
   # Inside VM
   ps aux | grep port-forward
   ```

3. **Verify service is running:**
   ```bash
   kubectl get pods -n <namespace>
   kubectl get svc -n <namespace>
   ```

4. **Test from inside VM first:**
   ```bash
   curl localhost:3000
   ```

### Port already in use

```bash
# On Windows (PowerShell as Admin)
netstat -ano | findstr :3000
taskkill /PID <pid> /F

# Inside VM
lsof -i :3000
kill <pid>
```

### Connection refused

Ensure you're using `--address 0.0.0.0` with kubectl port-forward. Without it, the port only binds to localhost inside the VM.

```bash
# Wrong - only accessible inside VM
kubectl port-forward svc/grafana 3000:80

# Correct - accessible from Windows
kubectl port-forward --address 0.0.0.0 svc/grafana 3000:80
```
