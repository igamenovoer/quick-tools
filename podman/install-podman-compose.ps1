<#
.SYNOPSIS
    Installs Docker Compose for Podman on Windows.

.DESCRIPTION
    This script installs Docker Compose (the official Docker Compose v2 binary) which works
    seamlessly with Podman through its Docker-compatible socket API. This is the same approach
    used by Podman Desktop's "Setup Compose" feature.
    
    Downloads the official Docker Compose v2 binary from GitHub releases and installs it
    to C:\Program Files\Docker\docker-compose.exe, making it available for both 'docker-compose'
    and 'podman compose' commands.

.PARAMETER Version
    Specific version to install (e.g., 'v2.40.3'). If not specified, installs the latest version.

.EXAMPLE
    .\install-podman-compose.ps1
    Installs the latest Docker Compose v2 binary.

.EXAMPLE
    .\install-podman-compose.ps1 -Version v2.40.3
    Installs specific version of Docker Compose.

.NOTES
    Author: Quick Tools
    Date: 2025-11-16
    
    This script replicates Podman Desktop's compose installation:
    - Downloads official Docker Compose v2 from GitHub releases
    - Installs to C:\Program Files\Docker\docker-compose.exe
    - Works with Podman through Docker-compatible socket
    - No Python dependency required
    - Latest version: v2.40.3 (as of Nov 2025)
    
    For more information:
    - Docker Compose: https://github.com/docker/compose
    - Podman Desktop: https://podman-desktop.io/docs/compose/setting-up-compose
#>

[CmdletBinding()]
param(
    [Parameter(HelpMessage="Specific version to install (e.g., 'v2.40.3')")]
    [string]$Version
)

# Set error action preference
$ErrorActionPreference = "Stop"

# Check if running as administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "This script requires administrator privileges." -ForegroundColor Yellow
    Write-Host "Restarting with elevated permissions..." -ForegroundColor Yellow
    Write-Host ""
    
    # Build the argument list
    $scriptPath = $MyInvocation.MyCommand.Path
    $argList = "-NoExit", "-Command", "& { cd '$PWD'; & '$scriptPath'"
    
    # Add parameters if provided
    if ($Version) {
        $argList += "-Version '$Version'"
    }
    
    $argList += "; Write-Host ''; Read-Host 'Press Enter to close' }"
    
    # Start new PowerShell process with admin rights
    try {
        Start-Process powershell -Verb RunAs -ArgumentList $argList
        exit 0
    }
    catch {
        Write-Host "Failed to elevate privileges. Please run PowerShell as Administrator manually." -ForegroundColor Red
        Write-Host ""
        Read-Host "Press Enter to exit"
        exit 1
    }
}

Write-Host "=== Podman Compose Installer for Windows ===" -ForegroundColor Cyan
Write-Host "Installing Docker Compose v2 (same as Podman Desktop)" -ForegroundColor Cyan
Write-Host ""

# Function to check if a command exists
function Test-CommandExists {
    param($Command)
    $null -ne (Get-Command $Command -ErrorAction SilentlyContinue)
}

# Function to get latest GitHub release version
function Get-LatestGitHubRelease {
    param([string]$Repo)
    try {
        $apiUrl = "https://api.github.com/repos/$Repo/releases/latest"
        $response = Invoke-RestMethod -Uri $apiUrl -ErrorAction Stop
        return $response.tag_name
    }
    catch {
        Write-Host "Warning: Could not fetch latest version from GitHub. Using fallback." -ForegroundColor Yellow
        return $null
    }
}

# Main installation flow
Write-Host "[1/5] Checking Podman installation..." -ForegroundColor Yellow
if (-not (Test-CommandExists "podman")) {
    Write-Host "ERROR: Podman is not installed or not in PATH." -ForegroundColor Red
    Write-Host "Please install Podman first:" -ForegroundColor Red
    Write-Host "  - Download: https://podman.io/getting-started/installation" -ForegroundColor Gray
    Write-Host "  - Or run: winget install RedHat.Podman" -ForegroundColor Gray
    exit 1
}

$podmanVersion = (podman --version 2>&1) -replace '.*version\s+', ''
Write-Host "  ✓ Podman found: version $podmanVersion" -ForegroundColor Green
Write-Host ""

# Check if compose is already installed
Write-Host "[2/5] Checking for existing Compose installation..." -ForegroundColor Yellow

if (Test-CommandExists "docker-compose") {
    try {
        $installedVersion = (docker-compose version --short 2>&1) | Out-String
        $installedVersion = $installedVersion.Trim()
        Write-Host "  ✓ Docker Compose is already installed" -ForegroundColor Green
        Write-Host "  Version: $installedVersion" -ForegroundColor Green
    }
    catch {
        Write-Host "  ✓ Docker Compose is already installed" -ForegroundColor Green
    }
    Write-Host ""
    Write-Host "Compose is already installed. Skipping installation." -ForegroundColor Cyan
    Write-Host ""
    Write-Host "To reinstall or upgrade:" -ForegroundColor Yellow
    Write-Host "  1. Remove existing: Remove-Item '$env:ProgramFiles\Docker\docker-compose.exe' -Force" -ForegroundColor Gray
    Write-Host "  2. Run this script again" -ForegroundColor Gray
    Write-Host ""
    exit 0
}

Write-Host "  No existing installation found. Proceeding with installation..." -ForegroundColor Yellow
Write-Host ""

# Determine version to install
Write-Host "[3/5] Determining version to install..." -ForegroundColor Yellow

if (-not $Version) {
    $Version = Get-LatestGitHubRelease -Repo "docker/compose"
    if (-not $Version) {
        $Version = "v2.40.3"  # Fallback to known stable version
        Write-Host "  Using fallback version: $Version" -ForegroundColor Yellow
    }
}

Write-Host "  Target version: $Version" -ForegroundColor Green
Write-Host ""

# Download and install
Write-Host "[4/5] Downloading Docker Compose $Version..." -ForegroundColor Yellow

# Determine architecture
$arch = "x86_64"
if ([Environment]::Is64BitOperatingSystem) {
    # Check if we're on ARM64
    try {
        $processor = (Get-WmiObject Win32_Processor).Architecture
        if ($processor -eq 12) {  # ARM64
            $arch = "aarch64"
        }
    }
    catch {
        # Default to x86_64 if we can't determine
    }
}

$downloadUrl = "https://github.com/docker/compose/releases/download/$Version/docker-compose-windows-$arch.exe"
$installPath = "$env:ProgramFiles\Docker"
$exePath = "$installPath\docker-compose.exe"

Write-Host "  Download URL: $downloadUrl" -ForegroundColor Gray
Write-Host "  Install path: $exePath" -ForegroundColor Gray

# Create directory if it doesn't exist
if (-not (Test-Path $installPath)) {
    Write-Host "  Creating directory: $installPath" -ForegroundColor Gray
    try {
        New-Item -ItemType Directory -Path $installPath -Force | Out-Null
    }
    catch {
        Write-Host "ERROR: Failed to create directory. Run as administrator." -ForegroundColor Red
        throw $_
    }
}

# Download the binary
try {
    Write-Host "  Downloading... (this may take a moment)" -ForegroundColor Gray
    Invoke-WebRequest -Uri $downloadUrl -OutFile $exePath -ErrorAction Stop
    Write-Host "  ✓ Downloaded successfully" -ForegroundColor Green
}
catch {
    Write-Host "ERROR: Failed to download Docker Compose." -ForegroundColor Red
    Write-Host "Error: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please check:" -ForegroundColor Yellow
    Write-Host "  - Your internet connection" -ForegroundColor Gray
    Write-Host "  - The version exists: $downloadUrl" -ForegroundColor Gray
    Write-Host "  - You have permission to write to $installPath" -ForegroundColor Gray
    throw $_
}

# Add to PATH if not already there
$currentPath = [Environment]::GetEnvironmentVariable("Path", "Machine")
if ($currentPath -notlike "*$installPath*") {
    Write-Host "  Adding $installPath to system PATH..." -ForegroundColor Gray
    try {
        [Environment]::SetEnvironmentVariable("Path", "$currentPath;$installPath", "Machine")
        $env:Path = "$env:Path;$installPath"
        Write-Host "  ✓ PATH updated" -ForegroundColor Green
    }
    catch {
        Write-Host "  ⚠ Could not update PATH. You may need to add it manually." -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "[5/5] Verifying installation..." -ForegroundColor Yellow

# Refresh PATH in current session
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

Start-Sleep -Seconds 1

if (Test-Path $exePath) {
    try {
        $version = & $exePath version 2>&1
        Write-Host "  ✓ Docker Compose installed successfully!" -ForegroundColor Green
        Write-Host "  Version: $($version | Select-Object -First 1)" -ForegroundColor Green
    }
    catch {
        Write-Host "  ✓ Binary installed at: $exePath" -ForegroundColor Green
        Write-Host "  ⚠ Could not verify version (may need terminal restart)" -ForegroundColor Yellow
    }
}
else {
    Write-Host "  ⚠ Installation completed but binary not found" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== Installation Complete ===" -ForegroundColor Green
Write-Host ""
Write-Host "Usage examples:" -ForegroundColor Cyan
Write-Host "  docker-compose version            # Check version" -ForegroundColor Gray
Write-Host "  podman compose version            # Podman integration" -ForegroundColor Gray
Write-Host "  docker-compose up -d              # Start containers" -ForegroundColor Gray
Write-Host "  podman compose up -d              # Same with podman" -ForegroundColor Gray
Write-Host ""
Write-Host "Note: Docker Compose v2 works with Podman through its Docker-compatible socket." -ForegroundColor Cyan
Write-Host "This is the same method used by Podman Desktop." -ForegroundColor Cyan
Write-Host ""
Write-Host "For more info: https://github.com/docker/compose" -ForegroundColor Gray
Write-Host ""

if (-not (Test-CommandExists "docker-compose")) {
    Write-Host "NOTE: Command not immediately available. Please restart your terminal." -ForegroundColor Yellow
    Write-Host ""
}
