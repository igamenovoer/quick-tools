<#
.SYNOPSIS
    Downloads VS Code installer / archive for a target platform.

.DESCRIPTION
    Downloads the Visual Studio Code installer (or archive) to the specified directory.
    Supports downloading specific versions or the latest stable version, and allows
    choosing the target platform (e.g. win32-x64, linux-x64, linux-arm64).

.PARAMETER OutputDir
    Output directory where the installer will be saved. 
    Default: Current working directory (pwd)

.PARAMETER TargetVersion
    Specific VS Code version to download (e.g., "1.105.1").
    If not specified, downloads the latest stable version.

.PARAMETER Platform
    Target platform identifier used by the VS Code update service, such as:
      - "win32-x64" (Windows x64 user installer; mapped to win32-x64-user)
      - "win32-x64-user" (Windows x64 user installer)
      - "win32-arm64" (Windows ARM64 user installer; mapped to win32-arm64-user)
      - "win32-arm64-user" (Windows ARM64 user installer)
      - "linux-x64" (Linux x64 .tar.gz)
      - "linux-arm64" (Linux ARM64 .tar.gz)
      - "darwin-x64" (macOS Intel .zip)
      - "darwin-arm64" (macOS Apple Silicon .zip)

    If not specified, defaults to Windows x64 user installer (win32-x64-user),
    preserving the original behavior of this script.

.EXAMPLE
    .\get-vscode.ps1
    Downloads latest version to current directory

.EXAMPLE
    .\get-vscode.ps1 -OutputDir "C:\Temp\vscode"
    Downloads latest version to C:\Temp\vscode

.EXAMPLE
    .\get-vscode.ps1 -OutputDir "C:\Temp" -TargetVersion "1.105.1"
    Downloads version 1.105.1 to C:\Temp

.EXAMPLE
    .\get-vscode.ps1 -Platform "linux-x64"
    Downloads the latest Linux x64 VS Code .tar.gz to the current directory.

.EXAMPLE
    .\get-vscode.ps1 -Platform "linux-arm64" -TargetVersion "1.105.1"
    Downloads the Linux ARM64 tarball for version 1.105.1.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$OutputDir = (Get-Location).Path,
    
    [Parameter(Mandatory=$false)]
    [string]$TargetVersion = "",

    [Parameter(Mandatory=$false)]
    [string]$Platform = ""
)

$ErrorActionPreference = "Stop"

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "VS Code Installer Downloader" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Create output directory if it doesn't exist
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
    Write-Host "Created output directory: $OutputDir" -ForegroundColor Green
}

# Resolve to absolute path
$OutputDir = (Resolve-Path $OutputDir).Path

# Function to get latest VS Code version
function Get-LatestVSCodeVersion {
    Write-Host "Fetching latest VS Code version information..." -ForegroundColor Yellow
    
    try {
        # VS Code updates API endpoint (Windows x64 user installer is sufficient
        # to discover the latest product version and commit hash)
        $apiUrl = "https://update.code.visualstudio.com/api/update/win32-x64-user/stable/latest"
        $response = Invoke-RestMethod -Uri $apiUrl -Method Get
        
        return @{
            Version = $response.productVersion
            Commit = $response.version
            Timestamp = $response.timestamp
        }
    }
    catch {
        Write-Host "  ERROR: Could not fetch latest version info: $_" -ForegroundColor Red
        return $null
    }
}

# Function to download file with progress
function Download-File {
    param(
        [string]$Url,
        [string]$OutputPath,
        [string]$Description
    )
    
    Write-Host "`nDownloading: $Description" -ForegroundColor Yellow
    Write-Host "  URL: $Url"
    Write-Host "  Output: $OutputPath"
    Write-Host "  Press Ctrl+C to cancel...`n"
    
    try {
        # Use Invoke-WebRequest with -OutFile for proper progress and Ctrl+C support
        $ProgressPreference = 'Continue'
        Invoke-WebRequest -Uri $Url -OutFile $OutputPath -UseBasicParsing
        
        # Check if file was downloaded successfully
        if (Test-Path $OutputPath) {
            $fileSize = (Get-Item $OutputPath).Length / 1MB
            if ($fileSize -gt 0) {
                Write-Host "`n  Downloaded: $([math]::Round($fileSize, 2)) MB" -ForegroundColor Green
                return $true
            }
            else {
                Write-Host "`n  ERROR: Download incomplete" -ForegroundColor Red
                Remove-Item $OutputPath -Force -ErrorAction SilentlyContinue
                return $false
            }
        }
        else {
            Write-Host "`n  ERROR: Download failed" -ForegroundColor Red
            return $false
        }
    }
    catch [System.Management.Automation.PipelineStoppedException] {
        Write-Host "`n  Download cancelled by user" -ForegroundColor Yellow
        if (Test-Path $OutputPath) {
            Remove-Item $OutputPath -Force -ErrorAction SilentlyContinue
        }
        return $false
    }
    catch {
        Write-Host "`n  ERROR: Failed to download - $($_.Exception.Message)" -ForegroundColor Red
        
        if (Test-Path $OutputPath) {
            Remove-Item $OutputPath -Force -ErrorAction SilentlyContinue
        }
        return $false
    }
}

# Determine version to download
$vscodeVersion = ""
$commitHash = ""

if ([string]::IsNullOrEmpty($TargetVersion)) {
    # Fetch latest version
    Write-Host "No version specified, fetching latest stable version..." -ForegroundColor Cyan
    $versionInfo = Get-LatestVSCodeVersion
    
    if ($null -eq $versionInfo) {
        Write-Host "ERROR: Could not determine latest version. Please specify -TargetVersion parameter." -ForegroundColor Red
        exit 1
    }
    
    $vscodeVersion = $versionInfo.Version
    $commitHash = $versionInfo.Commit
    Write-Host "Latest version: $vscodeVersion (Commit: $commitHash)" -ForegroundColor Green
}
else {
    $vscodeVersion = $TargetVersion
    Write-Host "Target version: $vscodeVersion" -ForegroundColor Green
}

# Determine effective platform segment for the update service
# Default: preserve original behavior (Windows x64 user installer)
if ([string]::IsNullOrEmpty($Platform)) {
    $platformSegment = "win32-x64-user"
} else {
    # Map extension-style Windows platform identifiers to user installers
    if ($Platform -match "^win32-(x64|arm64)$") {
        $platformSegment = "$Platform-user"
    }
    else {
        $platformSegment = $Platform
    }
}

Write-Host "Target platform: $platformSegment" -ForegroundColor Green

# Build download URL and output filename
# VS Code download URL format: https://update.code.visualstudio.com/{version}/{platform}/stable
$downloadUrl = "https://update.code.visualstudio.com/$vscodeVersion/$platformSegment/stable"

# Derive a reasonable file name based on platform
if ([string]::IsNullOrEmpty($Platform) -and $platformSegment -eq "win32-x64-user") {
    # Preserve original Windows user installer naming
    $outputFileName = "VSCodeUserSetup-x64-$vscodeVersion.exe"
}
else {
    # Heuristic for file extension based on platform
    if ($platformSegment -like "win32-*") {
        $fileExt = ".exe"
    }
    elseif ($platformSegment -like "linux-*" -or $platformSegment -like "alpine-*") {
        $fileExt = ".tar.gz"
    }
    elseif ($platformSegment -like "darwin*") {
        $fileExt = ".zip"
    }
    else {
        # Fallback: no extension; server may still respond with a useful file
        $fileExt = ""
    }

    $outputFileName = "VSCode-$platformSegment-$vscodeVersion$fileExt"
}

$outputPath = Join-Path $OutputDir $outputFileName

Write-Host "`nPreparing to download VS Code..." -ForegroundColor Cyan
Write-Host "  Version: $vscodeVersion"
Write-Host "  Platform segment: $platformSegment"
Write-Host "  Output: $outputPath`n"

# Download VS Code installer
$success = Download-File -Url $downloadUrl -OutputPath $outputPath -Description "VS Code $vscodeVersion Installer"

if ($success) {
    Write-Host "`n========================================" -ForegroundColor Green
    Write-Host "Download Complete!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "`nInstaller location:" -ForegroundColor Cyan
    Write-Host "  $outputPath" -ForegroundColor White
    Write-Host "`nTo install VS Code, run:" -ForegroundColor Cyan
    Write-Host "  & '$outputPath'" -ForegroundColor White
    exit 0
}
else {
    Write-Host "`n========================================" -ForegroundColor Red
    Write-Host "Download Failed!" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    exit 1
}
