Param()

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Push-Location $scriptDir
try {
    $image = "localhost/vscode-airgap-terminal:latest"
    $containerName = "vscode-terminal-x11-test"

    Write-Host "[info] Using image: $image" -ForegroundColor Cyan

    Write-Host "[info] Checking if image exists..." -ForegroundColor Cyan
    podman image exists $image | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[info] Image missing, building from terminal.Dockerfile ..." -ForegroundColor Yellow
        podman build --no-cache -f terminal.Dockerfile -t $image .
    }

    Write-Host "[info] Verifying WSLg X11 socket inside podman machine..." -ForegroundColor Cyan
    podman machine ssh podman-machine-default 'test -S /mnt/wslg/.X11-unix/X0' 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[error] /mnt/wslg/.X11-unix/X0 not found inside podman machine." -ForegroundColor Red
        Write-Host "        Make sure WSLg is running and Podman is configured to use WSLg." -ForegroundColor Red
        exit 1
    }

    Write-Host "[info] Starting test container $containerName with X11 forwarding..." -ForegroundColor Cyan
    Write-Host "       If everything is wired correctly, an xclock window should appear." -ForegroundColor Cyan

    podman run --rm -it `
      --name $containerName `
      -e DISPLAY=":0" `
      -v /mnt/wslg/.X11-unix:/tmp/.X11-unix `
      $image `
      xclock
}
finally {
    Pop-Location
}
