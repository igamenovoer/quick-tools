Param()

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Push-Location $scriptDir
try {
    $terminalContainer = "vscode-terminal"
    $terminalUser = "vscode-tester"

    Write-Host "[info] Launching VS Code from running terminal container..." -ForegroundColor Cyan
    Write-Host "[info] Container : $terminalContainer" -ForegroundColor DarkCyan
    Write-Host "[info] User      : $terminalUser" -ForegroundColor DarkCyan
    Write-Host "" 

    Write-Host "[info] Checking if container exists..." -ForegroundColor Cyan
    podman container exists $terminalContainer 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[error] Container '$terminalContainer' not found." -ForegroundColor Red
        Write-Host "[info] Start the stack first, for example:" -ForegroundColor Yellow
        Write-Host "  cd install-vscode-offline/simulate" -ForegroundColor White
        Write-Host "  .\\start-both.ps1" -ForegroundColor White
        exit 1
    }

    $status = podman container inspect $terminalContainer --format "{{.State.Status}}" 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $status) {
        Write-Host "[error] Failed to inspect container '$terminalContainer'." -ForegroundColor Red
        exit 1
    }

    if ($status -ne "running") {
        Write-Host "[error] Container '$terminalContainer' exists but is not running (status: $status)." -ForegroundColor Red
        Write-Host "[info] Try:" -ForegroundColor Yellow
        Write-Host "  cd install-vscode-offline/simulate" -ForegroundColor White
        Write-Host "  .\\start-both.ps1" -ForegroundColor White
        exit 1
    }

    Write-Host "[success] Container '$terminalContainer' is running." -ForegroundColor Green
    Write-Host "[info] VS Code should appear via WSLg; close it to return." -ForegroundColor Cyan
    Write-Host "" 

    podman exec -it `
      --user $terminalUser `
      -e DISPLAY=":0" `
      -e DONT_PROMPT_WSL_INSTALL="1" `
      $terminalContainer `
      bash -lc 'DISPLAY=${DISPLAY:-:0} DONT_PROMPT_WSL_INSTALL=1 code --disable-gpu --no-sandbox --disable-dev-shm-usage --verbose'
}
finally {
    Pop-Location
}
