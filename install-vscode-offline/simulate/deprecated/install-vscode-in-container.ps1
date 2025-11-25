Param(
    [string]$ContainerName = "vscode-terminal"
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Push-Location $scriptDir
try {
    $installScript = Join-Path $scriptDir "helper-scripts\terminal-install-in-container.sh"

    Write-Host "[info] VS Code Installation Script for Terminal Container" -ForegroundColor Cyan
    Write-Host "[info] Container: $ContainerName" -ForegroundColor Cyan
    Write-Host ""

    # Check if container exists and is running
    Write-Host "[info] Checking container status..." -ForegroundColor Cyan
    $containerStatus = podman container inspect $ContainerName --format "{{.State.Status}}" 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[error] Container '$ContainerName' not found" -ForegroundColor Red
        Write-Host "[info] Please start the container first:" -ForegroundColor Yellow
        Write-Host "  podman run -d --name $ContainerName ... localhost/vscode-airgap-terminal:latest sleep infinity" -ForegroundColor Yellow
        exit 1
    }

    if ($containerStatus -ne "running") {
        Write-Host "[error] Container '$ContainerName' is not running (status: $containerStatus)" -ForegroundColor Red
        Write-Host "[info] Start it with: podman start $ContainerName" -ForegroundColor Yellow
        exit 1
    }

    Write-Host "[info] Container is running" -ForegroundColor Green
    Write-Host ""

    # Check if script file exists
    if (-not (Test-Path $installScript)) {
        Write-Host "[error] Installation script not found: $installScript" -ForegroundColor Red
        exit 1
    }

    Write-Host "[info] Copying installation script to container..." -ForegroundColor Cyan
    podman cp $installScript "${ContainerName}:/tmp/terminal-install-in-container.sh"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[error] Failed to copy script to container" -ForegroundColor Red
        exit 1
    }

    Write-Host "[info] Making script executable..." -ForegroundColor Cyan
    podman exec $ContainerName chmod +x /tmp/terminal-install-in-container.sh

    Write-Host "[info] Running installation script..." -ForegroundColor Cyan
    Write-Host ""
    Write-Host "=========================================" -ForegroundColor Cyan

    # Run the script in the container
    podman exec -it $ContainerName bash /tmp/terminal-install-in-container.sh

    Write-Host "=========================================" -ForegroundColor Cyan
    Write-Host ""

    if ($LASTEXITCODE -eq 0) {
        Write-Host "[success] Installation script completed successfully" -ForegroundColor Green
    } else {
        Write-Host "[error] Installation script failed with exit code: $LASTEXITCODE" -ForegroundColor Red
        exit 1
    }

    Write-Host ""
    Write-Host "[info] Cleaning up..." -ForegroundColor Cyan
    podman exec $ContainerName rm -f /tmp/terminal-install-in-container.sh

    Write-Host ""
    Write-Host "[info] To launch VS Code GUI:" -ForegroundColor Cyan
    Write-Host "  podman exec -it $ContainerName bash -c `"code --disable-gpu --no-sandbox --disable-dev-shm-usage`"" -ForegroundColor Yellow
}
finally {
    Pop-Location
}
