# Shared configuration and functions for minikube Hyper-V scripts
# Sourced by setup-hyperv.ps1 and start-hyperv.ps1

$MINIKUBE_DIR = "C:\Work\mini-vbox"
$MINIKUBE_EXE = Join-Path $MINIKUBE_DIR "minikube.exe"
$KUBECTL_EXE = Join-Path $MINIKUBE_DIR "kubectl.exe"
$NODES = 3
$CPUS_PER_NODE = 7
$MEMORY_PER_NODE = 12288
$DISK_SIZE = "40g"
$EXTRA_DISK_SIZE = 20GB
$K8S_VERSION = "v1.35.0"

# Registry hostnames that need IPv4-only /etc/hosts entries.
# Hyper-V VMs have no IPv6 routing — DNS returns AAAA records, Go/Docker tries
# IPv6 first and fails. We resolve A records from the host and inject them.
$REGISTRY_HOSTS = @(
    "registry.k8s.io",
    "europe-west10-docker.pkg.dev",
    "registry-1.docker.io",
    "production.cloudflare.docker.com",
    "quay.io",
    "gcr.io",
    "cdn03.quay.io",
    "docker.io",
    "us-docker.pkg.dev",
    "cdn01.quay.io",
    "cdn02.quay.io"
)

function Fix-RegistryAccess {
    param([string[]]$NodeNames)

    # Resolve IPv4 addresses from the host (which has working DNS)
    $hostsEntries = @()
    foreach ($host_ in $REGISTRY_HOSTS) {
        try {
            $ip = (Resolve-DnsName -Name $host_ -Type A -DnsOnly -ErrorAction Stop |
                   Where-Object { $_.Type -eq "A" } |
                   Select-Object -First 1).IPAddress
            if ($ip) {
                $hostsEntries += "$ip $host_"
            }
        } catch {
            Write-Host "[WARNING] Could not resolve $host_ - skipping" -ForegroundColor Yellow
        }
    }

    if ($hostsEntries.Count -eq 0) {
        Write-Host "[WARNING] No registry IPs resolved - image pulls may fail" -ForegroundColor Yellow
        return
    }

    # Build a single command to inject all entries into /etc/hosts
    $entriesBlock = ($hostsEntries | ForEach-Object { $_ }) -join "\n"
    # Use a marker so we can cleanly replace on re-runs
    $sshCmd = @(
        "sudo sed -i '/# MINIKUBE-REGISTRY-FIX/,/# END-MINIKUBE-REGISTRY-FIX/d' /etc/hosts",
        "echo -e '# MINIKUBE-REGISTRY-FIX\n$entriesBlock\n# END-MINIKUBE-REGISTRY-FIX' | sudo tee -a /etc/hosts > /dev/null",
        "sudo systemctl restart docker"
    ) -join " && "

    foreach ($name in $NodeNames) {
        & $MINIKUBE_EXE ssh -n $name -- $sshCmd 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[SUCCESS] Registry /etc/hosts fix applied on $name" -ForegroundColor Green
        } else {
            Write-Host "[WARNING] Failed to apply fix on $name" -ForegroundColor Yellow
        }
    }

    Write-Host "[INFO] Resolved entries:" -ForegroundColor Cyan
    foreach ($entry in $hostsEntries) {
        Write-Host "  $entry"
    }
}

function Get-AllNodeNames {
    $names = @("minikube")
    for ($i = 2; $i -le $NODES; $i++) {
        $names += "minikube-m{0:D2}" -f $i
    }
    return $names
}
