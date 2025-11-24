# Install Podman Engine on Windows via WinGet
# This script installs Podman Desktop which includes the Podman engine

Write-Host "Installing Podman Engine on Windows..." -ForegroundColor Green

# Check if winget is available
Write-Host "`nChecking WinGet availability..." -ForegroundColor Yellow
$wingetPath = Get-Command winget -ErrorAction SilentlyContinue
if (-not $wingetPath) {
    Write-Host "Error: WinGet is not installed. Please install App Installer from Microsoft Store." -ForegroundColor Red
    exit 1
}
Write-Host "WinGet found." -ForegroundColor Green

# Check if Podman is already installed
Write-Host "`nChecking if Podman is already installed..." -ForegroundColor Yellow
$podmanPath = Get-Command podman -ErrorAction SilentlyContinue

if ($podmanPath) {
    $podmanVersion = podman --version 2>$null
    Write-Host "Podman is already installed: $podmanVersion" -ForegroundColor Green

    Write-Host "`nWould you like to reinstall/upgrade? (y/N): " -ForegroundColor Yellow -NoNewline
    $response = Read-Host
    if ($response -ne 'y' -and $response -ne 'Y') {
        Write-Host "Installation cancelled." -ForegroundColor Yellow
        exit 0
    }
}

# Install Podman via WinGet
Write-Host "`nInstalling Podman via WinGet..." -ForegroundColor Yellow
Write-Host "Running: winget install RedHat.Podman" -ForegroundColor Cyan

winget install RedHat.Podman --accept-package-agreements --accept-source-agreements

if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne -1978335189) {
    # -1978335189 means "already installed" which is OK
    Write-Host "`nError: Failed to install Podman. Exit code: $LASTEXITCODE" -ForegroundColor Red
    exit 1
}

Write-Host "`n==================================================" -ForegroundColor Green
Write-Host "Podman Engine installed successfully!" -ForegroundColor Green
Write-Host "==================================================" -ForegroundColor Green

# Refresh PATH for current session
Write-Host "`nRefreshing PATH environment..." -ForegroundColor Yellow
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

# Verify installation
Write-Host "`nVerifying installation..." -ForegroundColor Yellow
$newPodmanPath = Get-Command podman -ErrorAction SilentlyContinue

if ($newPodmanPath) {
    $version = podman --version
    Write-Host "Podman installed successfully: $version" -ForegroundColor Green
} else {
    Write-Host "Note: Podman installed but not yet in PATH." -ForegroundColor Yellow
    Write-Host "Please restart your terminal or log out/in to refresh PATH." -ForegroundColor Yellow
}

Write-Host "`nNext steps:" -ForegroundColor Cyan
Write-Host "  1. Initialize a Podman machine:" -ForegroundColor White
Write-Host "     podman machine init" -ForegroundColor Gray
Write-Host "  2. Start the Podman machine:" -ForegroundColor White
Write-Host "     podman machine start" -ForegroundColor Gray
Write-Host "  3. Verify with:" -ForegroundColor White
Write-Host "     podman info" -ForegroundColor Gray
Write-Host "`nOptional: Run other scripts in this folder for additional setup:" -ForegroundColor Cyan
Write-Host "  - install-podman-compose.ps1  : Install podman-compose" -ForegroundColor White
Write-Host "  - install-nvidia-runtime.ps1  : Enable NVIDIA GPU support" -ForegroundColor White
Write-Host "  - make-docker-symlink.ps1     : Create docker -> podman alias" -ForegroundColor White
Write-Host "  - move-podman-storage-to.ps1  : Move Podman VM storage location" -ForegroundColor White
