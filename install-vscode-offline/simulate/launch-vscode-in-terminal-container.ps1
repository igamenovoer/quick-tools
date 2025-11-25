Param()

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Push-Location $scriptDir
try {
    $terminalContainer = "vscode-terminal"
    $terminalUser = "vscode-tester"

    Write-Host "[info] Launch VS Code GUI from terminal container" -ForegroundColor Cyan
    Write-Host "[info] Container    : $terminalContainer" -ForegroundColor DarkCyan
    Write-Host ""

    Write-Host "[info] Checking if terminal container exists..." -ForegroundColor Cyan
    podman container exists $terminalContainer 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[error] Container '$terminalContainer' not found." -ForegroundColor Red
        Write-Host "[info] Start the stack first (for example with start-both.ps1)." -ForegroundColor Yellow
        return
    }

    $status = podman container inspect $terminalContainer --format "{{.State.Status}}" 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $status) {
        Write-Host "[error] Failed to inspect container '$terminalContainer'." -ForegroundColor Red
        return
    }

    if ($status -ne "running") {
        Write-Host "[error] Container '$terminalContainer' is not running (status: $status)." -ForegroundColor Red
        return
    }

    Write-Host "[success] Container '$terminalContainer' is running." -ForegroundColor Green
    Write-Host "[info] Launching VS Code as user '$terminalUser'..." -ForegroundColor Cyan
    Write-Host "       A VS Code window should appear via WSLg; close it to return." -ForegroundColor Cyan
    Write-Host ""

    podman exec -it --user $terminalUser `
      $terminalContainer `
      bash -lc 'DISPLAY=${DISPLAY:-:0} DONT_PROMPT_WSL_INSTALL=1 code --disable-gpu --no-sandbox --disable-dev-shm-usage --verbose'

    Write-Host ""
    Write-Host "[info] VS Code process exited." -ForegroundColor Cyan
}
finally {
    Pop-Location
}
