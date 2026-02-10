# Remove Hyper-V external switch for minikube
# Run this from PowerShell (as Administrator)

$ErrorActionPreference = "Stop"

$switchName = "minikube-external"

Write-Host "[INFO] Removing Hyper-V external switch: $switchName" -ForegroundColor Yellow

# Check if switch exists
$existingSwitch = Get-VMSwitch -Name $switchName -ErrorAction SilentlyContinue

if ($existingSwitch) {
    # Check if any VMs are using this switch
    $vmsUsingSwitch = Get-VM | Where-Object { 
        (Get-VMNetworkAdapter -VM $_).SwitchName -eq $switchName 
    }
    
    if ($vmsUsingSwitch) {
        Write-Host "[WARNING] The following VMs are using this switch:" -ForegroundColor Yellow
        $vmsUsingSwitch | ForEach-Object { Write-Host "  - $($_.Name)" }
        Write-Host ""
        $confirm = Read-Host "Stop these VMs and remove switch? (yes/no)"
        
        if ($confirm -ne "yes") {
            Write-Host "[INFO] Cancelled" -ForegroundColor Cyan
            exit 0
        }
        
        # Stop VMs
        Write-Host "[INFO] Stopping VMs..." -ForegroundColor Yellow
        $vmsUsingSwitch | Stop-VM -Force
    }
    
    # Remove switch
    Remove-VMSwitch -Name $switchName -Force
    Write-Host "[SUCCESS] Removed external switch: $switchName" -ForegroundColor Green
} else {
    Write-Host "[INFO] Switch '$switchName' does not exist" -ForegroundColor Cyan
}

Write-Host ""
Write-Host "[INFO] Your network adapter should now be back to normal" -ForegroundColor Green
