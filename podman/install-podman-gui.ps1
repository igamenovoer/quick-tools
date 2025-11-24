<#
.SYNOPSIS
    Installs Podman Desktop GUI on Windows.

.DESCRIPTION
    This script installs Podman Desktop, the official GUI application for managing Podman.
    Installation methods (in order of preference):
    1. WinGet (recommended) - RedHat.PodmanDesktop
    2. Direct download from GitHub releases if WinGet fails

.PARAMETER UseGitHub
    Force download from GitHub instead of using WinGet.

.EXAMPLE
    .\install-podman-gui.ps1
    Installs Podman Desktop using WinGet (preferred method).

.EXAMPLE
    .\install-podman-gui.ps1 -UseGitHub
    Forces download and installation from GitHub releases.

.NOTES
    Author: Quick Tools
    Date: 2025-11-24

    Podman Desktop provides:
    - Graphical interface for container management
    - Easy machine setup and configuration
    - Image, container, and volume management
    - Compose file support
    - Extension system for additional features

    For more information: https://podman-desktop.io/
#>

[CmdletBinding()]
param(
    [Parameter(HelpMessage="Force download from GitHub instead of using WinGet")]
    [switch]$UseGitHub
)

$ErrorActionPreference = "Stop"

Write-Host "=== Podman Desktop Installer for Windows ===" -ForegroundColor Cyan
Write-Host ""

# Function to check if a command exists
function Test-CommandExists {
    param($Command)
    $null -ne (Get-Command $Command -ErrorAction SilentlyContinue)
}

# Function to get latest GitHub release
function Get-LatestGitHubRelease {
    param([string]$Repo)
    try {
        Write-Host "  Fetching latest release information from GitHub..." -ForegroundColor Gray
        $apiUrl = "https://api.github.com/repos/$Repo/releases/latest"
        $response = Invoke-RestMethod -Uri $apiUrl -ErrorAction Stop
        return $response
    }
    catch {
        Write-Host "  Warning: Could not fetch latest version from GitHub." -ForegroundColor Yellow
        Write-Host "  Error: $_" -ForegroundColor DarkGray
        return $null
    }
}

# Check if Podman Desktop is already installed
Write-Host "[1/3] Checking for existing Podman Desktop installation..." -ForegroundColor Yellow

$desktopInstalled = $false
$installedVersion = $null

# Check via WinGet
if (Test-CommandExists "winget") {
    try {
        $wingetList = winget list --id RedHat.PodmanDesktop --exact 2>&1 | Out-String
        if ($wingetList -match "RedHat.PodmanDesktop") {
            $desktopInstalled = $true
            # Try to extract version
            if ($wingetList -match "(\d+\.\d+\.\d+)") {
                $installedVersion = $matches[1]
            }
        }
    }
    catch {
        # Not found via winget
    }
}

# Check via Program Files
if (-not $desktopInstalled) {
    $possiblePaths = @(
        "$env:LOCALAPPDATA\Programs\Podman Desktop\Podman Desktop.exe",
        "$env:ProgramFiles\Podman Desktop\Podman Desktop.exe"
    )

    foreach ($path in $possiblePaths) {
        if (Test-Path $path) {
            $desktopInstalled = $true
            Write-Host "  ✓ Podman Desktop found at: $path" -ForegroundColor Green
            break
        }
    }
}

if ($desktopInstalled) {
    if ($installedVersion) {
        Write-Host "  ✓ Podman Desktop is already installed (version $installedVersion)" -ForegroundColor Green
    } else {
        Write-Host "  ✓ Podman Desktop is already installed" -ForegroundColor Green
    }
    Write-Host ""

    $response = Read-Host "Do you want to reinstall/upgrade? (y/N)"
    if ($response -ne 'y' -and $response -ne 'Y') {
        Write-Host "Installation cancelled." -ForegroundColor Yellow
        exit 0
    }
    Write-Host ""
}

# Try WinGet installation first (unless UseGitHub is specified)
if (-not $UseGitHub) {
    Write-Host "[2/3] Attempting installation via WinGet..." -ForegroundColor Yellow

    if (-not (Test-CommandExists "winget")) {
        Write-Host "  ✗ WinGet is not available on this system." -ForegroundColor Yellow
        Write-Host "  Falling back to GitHub download method..." -ForegroundColor Yellow
        Write-Host ""
        $UseGitHub = $true
    }
    else {
        Write-Host "  Running: winget install RedHat.PodmanDesktop" -ForegroundColor Gray
        Write-Host ""

        try {
            winget install RedHat.PodmanDesktop --accept-package-agreements --accept-source-agreements

            if ($LASTEXITCODE -eq 0) {
                Write-Host ""
                Write-Host "==================================================" -ForegroundColor Green
                Write-Host "Podman Desktop installed successfully via WinGet!" -ForegroundColor Green
                Write-Host "==================================================" -ForegroundColor Green
                Write-Host ""
                Write-Host "You can launch Podman Desktop from:" -ForegroundColor Cyan
                Write-Host "  - Start Menu -> Podman Desktop" -ForegroundColor White
                Write-Host "  - Or run: podman-desktop" -ForegroundColor White
                Write-Host ""
                Write-Host "For more information: https://podman-desktop.io/" -ForegroundColor Gray
                exit 0
            }
            else {
                Write-Host ""
                Write-Host "  ✗ WinGet installation failed (exit code: $LASTEXITCODE)" -ForegroundColor Yellow
                Write-Host "  Falling back to GitHub download method..." -ForegroundColor Yellow
                Write-Host ""
                $UseGitHub = $true
            }
        }
        catch {
            Write-Host ""
            Write-Host "  ✗ WinGet installation failed: $_" -ForegroundColor Yellow
            Write-Host "  Falling back to GitHub download method..." -ForegroundColor Yellow
            Write-Host ""
            $UseGitHub = $true
        }
    }
}

# GitHub installation method
if ($UseGitHub) {
    Write-Host "[2/3] Installing from GitHub releases..." -ForegroundColor Yellow

    # Get latest release
    $release = Get-LatestGitHubRelease -Repo "containers/podman-desktop"

    if (-not $release) {
        Write-Host ""
        Write-Host "ERROR: Could not fetch release information from GitHub." -ForegroundColor Red
        Write-Host "Please check your internet connection or visit:" -ForegroundColor Red
        Write-Host "  https://github.com/containers/podman-desktop/releases" -ForegroundColor Gray
        exit 1
    }

    $version = $release.tag_name -replace '^v', ''
    Write-Host "  Latest version: $version" -ForegroundColor Green

    # Find the Windows installer asset
    $asset = $release.assets | Where-Object { $_.name -match "podman-desktop.*\.exe$" -and $_.name -notmatch "Setup" } | Select-Object -First 1

    if (-not $asset) {
        # Try alternative pattern
        $asset = $release.assets | Where-Object { $_.name -match "\.exe$" } | Select-Object -First 1
    }

    if (-not $asset) {
        Write-Host ""
        Write-Host "ERROR: Could not find Windows installer in release assets." -ForegroundColor Red
        Write-Host "Available assets:" -ForegroundColor Yellow
        $release.assets | ForEach-Object { Write-Host "  - $($_.name)" -ForegroundColor Gray }
        Write-Host ""
        Write-Host "Please download manually from:" -ForegroundColor Red
        Write-Host "  https://github.com/containers/podman-desktop/releases/latest" -ForegroundColor Gray
        exit 1
    }

    $downloadUrl = $asset.browser_download_url
    $fileName = $asset.name
    $fileSize = [math]::Round($asset.size / 1MB, 2)

    Write-Host "  Installer: $fileName ($fileSize MB)" -ForegroundColor Green
    Write-Host ""

    # Download to system temp
    $tempDir = $env:TEMP
    $installerPath = Join-Path $tempDir $fileName

    Write-Host "[3/3] Downloading installer..." -ForegroundColor Yellow
    Write-Host "  URL: $downloadUrl" -ForegroundColor Gray
    Write-Host "  Destination: $installerPath" -ForegroundColor Gray
    Write-Host ""

    try {
        Write-Host "  Downloading... (this may take a few minutes)" -ForegroundColor Cyan

        # Download with progress
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $downloadUrl -OutFile $installerPath -ErrorAction Stop
        $ProgressPreference = 'Continue'

        Write-Host "  ✓ Download complete" -ForegroundColor Green
        Write-Host ""
    }
    catch {
        Write-Host ""
        Write-Host "ERROR: Failed to download installer." -ForegroundColor Red
        Write-Host "Error: $_" -ForegroundColor Red
        Write-Host ""
        Write-Host "Please check your internet connection or download manually from:" -ForegroundColor Yellow
        Write-Host "  https://github.com/containers/podman-desktop/releases/latest" -ForegroundColor Gray
        exit 1
    }

    # Run installer
    Write-Host "Starting installer..." -ForegroundColor Yellow
    Write-Host "Please follow the installation wizard." -ForegroundColor Cyan
    Write-Host ""

    try {
        # Run installer (user mode, will show GUI)
        $process = Start-Process -FilePath $installerPath -Wait -PassThru

        if ($process.ExitCode -eq 0) {
            Write-Host ""
            Write-Host "==================================================" -ForegroundColor Green
            Write-Host "Podman Desktop installed successfully!" -ForegroundColor Green
            Write-Host "==================================================" -ForegroundColor Green
        }
        else {
            Write-Host ""
            Write-Host "Installer exited with code: $($process.ExitCode)" -ForegroundColor Yellow
            Write-Host "Installation may have been cancelled or failed." -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host ""
        Write-Host "ERROR: Failed to run installer." -ForegroundColor Red
        Write-Host "Error: $_" -ForegroundColor Red
        Write-Host ""
        Write-Host "You can run the installer manually from:" -ForegroundColor Yellow
        Write-Host "  $installerPath" -ForegroundColor Gray
        exit 1
    }
    finally {
        # Clean up installer
        if (Test-Path $installerPath) {
            try {
                Start-Sleep -Seconds 2
                Remove-Item $installerPath -Force -ErrorAction SilentlyContinue
                Write-Host "Cleaned up temporary installer file." -ForegroundColor Gray
            }
            catch {
                Write-Host "Note: Temporary installer left at: $installerPath" -ForegroundColor DarkGray
            }
        }
    }
}

Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. Launch Podman Desktop from Start Menu" -ForegroundColor White
Write-Host "  2. Follow the setup wizard to initialize your Podman machine" -ForegroundColor White
Write-Host "  3. Use the GUI to manage containers, images, and volumes" -ForegroundColor White
Write-Host ""
Write-Host "For more information: https://podman-desktop.io/" -ForegroundColor Gray
Write-Host ""
