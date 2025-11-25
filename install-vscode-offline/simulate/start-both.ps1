Param(
    [switch]$Yes
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Push-Location $scriptDir

$composeFile = "podman-compose-both.yaml"
$terminalContainer = "vscode-terminal"
$serverContainer = "vscode-remote"

Write-Host "[info] Using compose file : $composeFile" -ForegroundColor Cyan

Write-Host "[info] Checking existing stack status..." -ForegroundColor Cyan
$stackRunning = $false

podman container exists $terminalContainer 2>$null
if ($LASTEXITCODE -eq 0) {
    $status = podman container inspect $terminalContainer --format "{{.State.Status}}" 2>$null
    if ($LASTEXITCODE -eq 0 -and $status -eq "running") {
        $stackRunning = $true
    }
}

if ($stackRunning) {
    Write-Host "[info] Terminal container '$terminalContainer' is already running." -ForegroundColor Yellow
    if ($Yes) {
        Write-Host "[info] --yes specified; restarting stack without prompting." -ForegroundColor Cyan
    } else {
        $answer = Read-Host "Do you want to restart the stack (podman-compose down + up)? [y/N]"
        if (-not ($answer -match '^(y|Y)$')) {
            Write-Host "[info] Leaving existing stack running. No changes made." -ForegroundColor Cyan
            return
        }
    }
    Write-Host "[info] Restarting stack (recreate containers)..." -ForegroundColor Cyan
} else {
    Write-Host "[info] Stack not running; starting containers with podman run..." -ForegroundColor Cyan
}

try {
    if ($stackRunning) {
        Write-Host "[info] Removing existing containers '$terminalContainer' and '$serverContainer'..." -ForegroundColor Cyan
        podman rm -f $terminalContainer $serverContainer 2>$null | Out-Null
    }

    # Ensure internal network exists so containers have no internet access
    $networkName = "vscode-airgap-both"
    Write-Host "[info] Ensuring internal network '$networkName' exists..." -ForegroundColor Cyan
    podman network exists $networkName | Out-Null
    if ($LASTEXITCODE -ne 0) {
        podman network create --internal $networkName | Out-Null
    }

    Write-Host "[info] Starting terminal container '$terminalContainer'..." -ForegroundColor Cyan
    podman run -d `
        --name $terminalContainer `
        --network $networkName `
        --shm-size=2gb `
        -e DISPLAY=":0" `
        -e DONT_PROMPT_WSL_INSTALL="1" `
        -v /mnt/wslg/.X11-unix:/tmp/.X11-unix `
        -v ./pkgs:/pkgs-host:ro `
        localhost/vscode-airgap-terminal:latest `
        sleep infinity | Out-Null

    Write-Host "[info] Starting server container '$serverContainer'..." -ForegroundColor Cyan
    podman run -d `
        --name $serverContainer `
        --network $networkName `
        -v ./pkgs:/pkgs-host:ro `
        localhost/vscode-airgap-server:latest `
        /bin/bash -c "/usr/local/bin/startup-info.sh && /usr/sbin/sshd -D" | Out-Null

    Write-Host "[success] Both containers are running on internal network '$networkName' (no internet access)." -ForegroundColor Green
}
finally {
    Pop-Location
}
