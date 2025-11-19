# Install NVIDIA Container Runtime for Podman on Windows
# Prerequisites:
# - Podman machine must be initialized and running
# - NVIDIA GPU driver installed on Windows host

Write-Host "Installing NVIDIA Container Runtime for Podman..." -ForegroundColor Green

# Check if podman machine exists
Write-Host "`nChecking Podman machine status..." -ForegroundColor Yellow
$machineList = podman machine list --format json | ConvertFrom-Json
if (-not $machineList -or $machineList.Count -eq 0) {
    Write-Host "Error: No Podman machine found. Please run 'podman machine init' first." -ForegroundColor Red
    exit 1
}

# Get the first machine name
$machineName = $machineList[0].Name
Write-Host "Found Podman machine: $machineName" -ForegroundColor Green

# Check if machine is running
if ($machineList[0].Running -eq $false) {
    Write-Host "Starting Podman machine..." -ForegroundColor Yellow
    podman machine start $machineName
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Error: Failed to start Podman machine." -ForegroundColor Red
        exit 1
    }
}

Write-Host "`nChecking if NVIDIA Container Toolkit is already installed..." -ForegroundColor Yellow

# Check if nvidia-ctk is already installed
$checkInstalled = podman machine ssh $machineName -- "which nvidia-ctk 2>/dev/null"
$isInstalled = $LASTEXITCODE -eq 0

if ($isInstalled) {
    Write-Host "NVIDIA Container Toolkit is already installed." -ForegroundColor Green
    
    # Check if CDI devices are available
    Write-Host "Verifying CDI configuration..." -ForegroundColor Yellow
    $cdiCheck = podman machine ssh $machineName -- "nvidia-ctk cdi list 2>&1"
    
    if ($cdiCheck -match "nvidia.com/gpu") {
        Write-Host "CDI devices are properly configured:" -ForegroundColor Green
        Write-Host $cdiCheck -ForegroundColor White
        
        Write-Host "`n==================================================" -ForegroundColor Green
        Write-Host "NVIDIA Container Runtime is ready to use!" -ForegroundColor Green
        Write-Host "==================================================" -ForegroundColor Green
        
        Write-Host "`nSkipping installation. To test GPU access, run:" -ForegroundColor Cyan
        Write-Host "  podman run --rm --device nvidia.com/gpu=all nvidia/cuda:11.0.3-base-ubuntu20.04 nvidia-smi" -ForegroundColor White
        exit 0
    } else {
        Write-Host "CDI specification not found. Regenerating..." -ForegroundColor Yellow
        podman machine ssh $machineName -- "sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml"
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "CDI specification regenerated successfully." -ForegroundColor Green
            podman machine ssh $machineName -- "nvidia-ctk cdi list"
            
            Write-Host "`nRestarting Podman machine to apply changes..." -ForegroundColor Yellow
            podman machine stop $machineName
            Start-Sleep -Seconds 2
            podman machine start $machineName
            
            Write-Host "`n==================================================" -ForegroundColor Green
            Write-Host "NVIDIA Container Runtime is ready to use!" -ForegroundColor Green
            Write-Host "==================================================" -ForegroundColor Green
            exit 0
        }
    }
}

Write-Host "`nInstalling NVIDIA Container Toolkit inside Podman machine..." -ForegroundColor Yellow

# Execute installation commands one by one to avoid line ending issues
Write-Host "Adding NVIDIA Container Toolkit repository..." -ForegroundColor Cyan
podman machine ssh $machineName -- "curl -s -L https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo | sudo tee /etc/yum.repos.d/nvidia-container-toolkit.repo > /dev/null"

if ($LASTEXITCODE -ne 0) {
    Write-Host "`nError: Failed to add NVIDIA Container Toolkit repository." -ForegroundColor Red
    exit 1
}

Write-Host "Installing nvidia-container-toolkit..." -ForegroundColor Cyan
podman machine ssh $machineName -- "sudo yum install -y nvidia-container-toolkit"

if ($LASTEXITCODE -ne 0) {
    Write-Host "`nError: Failed to install nvidia-container-toolkit." -ForegroundColor Red
    exit 1
}

Write-Host "Generating CDI specification..." -ForegroundColor Cyan
podman machine ssh $machineName -- "sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml"

if ($LASTEXITCODE -ne 0) {
    Write-Host "`nError: Failed to generate CDI specification." -ForegroundColor Red
    exit 1
}

Write-Host "Listing available CDI devices..." -ForegroundColor Cyan
podman machine ssh $machineName -- "nvidia-ctk cdi list"

Write-Host "`n==================================================" -ForegroundColor Green
Write-Host "NVIDIA Container Runtime installed successfully!" -ForegroundColor Green
Write-Host "==================================================" -ForegroundColor Green

Write-Host "`nRestarting Podman machine to apply changes..." -ForegroundColor Yellow
podman machine stop $machineName
if ($LASTEXITCODE -ne 0) {
    Write-Host "Warning: Failed to stop Podman machine cleanly." -ForegroundColor Yellow
}

Start-Sleep -Seconds 2

podman machine start $machineName
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Failed to restart Podman machine." -ForegroundColor Red
    exit 1
}

Write-Host "Podman machine restarted successfully." -ForegroundColor Green

Write-Host "`nTesting GPU access..." -ForegroundColor Yellow
Write-Host "Running: podman run --rm --device nvidia.com/gpu=all nvidia/cuda:11.0.3-base-ubuntu20.04 nvidia-smi" -ForegroundColor Cyan

podman run --rm --device nvidia.com/gpu=all nvidia/cuda:11.0.3-base-ubuntu20.04 nvidia-smi

if ($LASTEXITCODE -eq 0) {
    Write-Host "`n==================================================" -ForegroundColor Green
    Write-Host "GPU test successful! Your setup is ready." -ForegroundColor Green
    Write-Host "==================================================" -ForegroundColor Green
    Write-Host "`nTo use GPU in containers, add this flag:" -ForegroundColor Cyan
    Write-Host "  --device nvidia.com/gpu=all" -ForegroundColor White
} else {
    Write-Host "`nWarning: GPU test failed. Please check:" -ForegroundColor Yellow
    Write-Host "  1. NVIDIA GPU driver is installed on Windows" -ForegroundColor White
    Write-Host "  2. Podman machine has been restarted after installation" -ForegroundColor White
    Write-Host "`nTry restarting the Podman machine:" -ForegroundColor Cyan
    Write-Host "  podman machine stop && podman machine start" -ForegroundColor White
}
