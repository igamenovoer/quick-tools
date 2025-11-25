Param()

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Push-Location $scriptDir
try {
    $composeFile = "podman-compose-both.yaml"
    $terminalContainer = "vscode-terminal"

    Write-Host "[info] Checking if compose stack is running..." -ForegroundColor Cyan

    # Check if terminal container is running
    podman container exists $terminalContainer 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[info] Terminal container not found, starting compose stack..." -ForegroundColor Yellow
        podman-compose -f $composeFile up -d

        # Wait a moment for containers to fully start
        Write-Host "[info] Waiting for containers to initialize..." -ForegroundColor Cyan
        Start-Sleep -Seconds 3
    } else {
        Write-Host "[info] Terminal container already running" -ForegroundColor Green
    }

    Write-Host "[info] Launching VS Code GUI in terminal container..." -ForegroundColor Cyan
    Write-Host "       VS Code window should appear via WSLg" -ForegroundColor Cyan
    Write-Host "       Close VS Code to return to this shell" -ForegroundColor Cyan
    Write-Host ""

    # Launch VS Code with the necessary flags for container X11 operation
    podman exec -it $terminalContainer bash -c 'DISPLAY=${DISPLAY:-:0} code --disable-gpu --no-sandbox --disable-dev-shm-usage --verbose'

    Write-Host ""
    Write-Host "[info] VS Code closed" -ForegroundColor Cyan
    Write-Host "[info] Containers are still running. Use 'podman-compose -f $composeFile down' to stop them." -ForegroundColor Yellow
}
finally {
    Pop-Location
}
