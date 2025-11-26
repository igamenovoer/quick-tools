<#
.SYNOPSIS
    Downloads VS Code Server / CLI tarballs for a given VS Code version.

.DESCRIPTION
    Resolves the VS Code commit hash for a specified VS Code product version
    (or the latest stable), then downloads the corresponding VS Code Server
    (and/or CLI) tarball for an update service platform segment such as
    "server-linux-x64" or "cli-alpine-x64".

    This is intended for preparing offline Remote-SSH server images, matching
    the patterns used in simulate/pkgs/server (e.g.
    "vscode-server-linux-x64-<COMMIT>.tar.gz").

.PARAMETER Platform
    Target platform segment or shorthand. Supported values include:
      - "linux-x64"          -> server-linux-x64  (VS Code Server, Linux x64)
      - "linux-arm64"        -> server-linux-arm64
      - "server-linux-x64"   -> server-linux-x64
      - "server-linux-arm64" -> server-linux-arm64
      - "alpine-x64"         -> cli-alpine-x64   (VS Code CLI, Alpine x64)
      - "alpine-arm64"       -> cli-alpine-arm64
      - "cli-alpine-x64"     -> cli-alpine-x64
      - "cli-alpine-arm64"   -> cli-alpine-arm64

    You may also pass the full segment used by the update service, such as
    "server-linux-x64" or "cli-alpine-x64". Any other value will be rejected.

.PARAMETER OutputDir
    Output directory where the tarball will be saved.
    Default: current working directory (pwd).

.PARAMETER TargetCodeVersion
    VS Code product version to align with, e.g. "1.106.2".
    If not specified, the script will resolve the latest stable VS Code
    version and use its commit hash.

.EXAMPLE
    .\get-code-server.ps1 -Platform linux-x64 -OutputDir "C:\Temp\vscode-server"
    Downloads the VS Code Server tarball for Linux x64 matching the latest
    stable VS Code version.

.EXAMPLE
    .\get-code-server.ps1 -Platform server-linux-x64 -TargetCodeVersion "1.106.2" `
        -OutputDir "quick-tools\install-vscode-offline\simulate\pkgs\server"
    Downloads "vscode-server-linux-x64-<COMMIT>.tar.gz" for the given VS Code
    version into the server pkgs directory.

.EXAMPLE
    .\get-code-server.ps1 -Platform cli-alpine-x64 -TargetCodeVersion "1.106.2"
    Downloads the VS Code CLI tarball for Alpine x64 suitable for use with
    Remote-SSH in container images.

.NOTES
    This script downloads **VS Code Server / CLI from Microsoft**, not the
    third-party "code-server" project.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Platform,

    [Parameter(Mandatory = $false)]
    [string]$OutputDir = (Get-Location).Path,

    [Parameter(Mandatory = $false)]
    [string]$TargetCodeVersion = ""
)

$ErrorActionPreference = "Stop"

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "VS Code Server / CLI Downloader" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Create output directory if it doesn't exist
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
    Write-Host "Created output directory: $OutputDir" -ForegroundColor Green
}

# Resolve to absolute path
$OutputDir = (Resolve-Path $OutputDir).Path

Write-Host "Target platform identifier : $Platform" -ForegroundColor Cyan
if ([string]::IsNullOrEmpty($TargetCodeVersion)) {
    Write-Host "Target VS Code version    : latest (stable)" -ForegroundColor Cyan
} else {
    Write-Host "Target VS Code version    : $TargetCodeVersion" -ForegroundColor Cyan
}

# Function to resolve VS Code version -> commit hash
function Get-VSCodeVersionInfo {
    param(
        [string]$RequestedVersion
    )

    Write-Host "`nResolving VS Code version and commit hash..." -ForegroundColor Yellow

    # Helper to call the update API and extract version + commit
    function Invoke-VersionApi {
        param(
            [string]$Url,
            [string]$Label
        )

        Write-Host "  Version API URL ($Label): $Url" -ForegroundColor White
        $response = Invoke-RestMethod -Uri $Url -Method Get

        if (-not $response) {
            throw "Empty response from version API."
        }

        return @{
            Version = $response.productVersion
            Commit  = $response.version
        }
    }

    try {
        if ([string]::IsNullOrEmpty($RequestedVersion)) {
            # Latest stable version
            $apiUrl = "https://update.code.visualstudio.com/api/update/win32-x64-user/stable/latest"
            $info = Invoke-VersionApi -Url $apiUrl -Label "latest"
        }
        else {
            # Try version-specific API first
            $apiUrlSpecific = "https://update.code.visualstudio.com/api/update/win32-x64-user/stable/$RequestedVersion"
            try {
                $info = Invoke-VersionApi -Url $apiUrlSpecific -Label "specific"
            }
            catch {
                Write-Host "  WARNING: Version-specific API failed for $RequestedVersion. Falling back to latest: $($_.Exception.Message)" -ForegroundColor Yellow
                $apiUrlLatest = "https://update.code.visualstudio.com/api/update/win32-x64-user/stable/latest"
                $info = Invoke-VersionApi -Url $apiUrlLatest -Label "latest"
            }
        }

        Write-Host "  Resolved VS Code version: $($info.Version)" -ForegroundColor Green
        Write-Host "  Resolved commit hash    : $($info.Commit)" -ForegroundColor Green
        return $info
    }
    catch {
        Write-Host "  ERROR: Failed to resolve VS Code version/commit: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

# Function to download file with progress and simple validation
function Download-File {
    param(
        [string]$Url,
        [string]$OutputPath,
        [string]$Description
    )

    Write-Host "`nDownloading: $Description" -ForegroundColor Yellow
    Write-Host "  URL   : $Url"
    Write-Host "  Output: $OutputPath"
    Write-Host "  Press Ctrl+C to cancel...`n"

    try {
        $ProgressPreference = 'Continue'
        Invoke-WebRequest -Uri $Url -OutFile $OutputPath -UseBasicParsing

        if (Test-Path $OutputPath) {
            $fileSize = (Get-Item $OutputPath).Length / 1MB
            if ($fileSize -gt 0) {
                Write-Host "`n  Downloaded: $([math]::Round($fileSize, 2)) MB" -ForegroundColor Green
                return $true
            }
            else {
                Write-Host "`n  ERROR: Download incomplete (empty file)" -ForegroundColor Red
                Remove-Item $OutputPath -Force -ErrorAction SilentlyContinue
                return $false
            }
        }
        else {
            Write-Host "`n  ERROR: Download failed (file not found after download)" -ForegroundColor Red
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

# Map user-friendly platform to update service segment and filename prefix
function Resolve-CodeServerPlatform {
    param(
        [string]$PlatformInput
    )

    $p = $PlatformInput.ToLowerInvariant()

    switch ($p) {
        "linux-x64" {
            return @{
                Segment    = "server-linux-x64"
                FilePrefix = "vscode-server-linux-x64"
                Kind       = "server"
                Label      = "VS Code Server (Linux x64)"
            }
        }
        "linux-arm64" {
            return @{
                Segment    = "server-linux-arm64"
                FilePrefix = "vscode-server-linux-arm64"
                Kind       = "server"
                Label      = "VS Code Server (Linux ARM64)"
            }
        }
        "server-linux-x64" {
            return @{
                Segment    = "server-linux-x64"
                FilePrefix = "vscode-server-linux-x64"
                Kind       = "server"
                Label      = "VS Code Server (Linux x64)"
            }
        }
        "server-linux-arm64" {
            return @{
                Segment    = "server-linux-arm64"
                FilePrefix = "vscode-server-linux-arm64"
                Kind       = "server"
                Label      = "VS Code Server (Linux ARM64)"
            }
        }
        "alpine-x64" {
            return @{
                Segment    = "cli-alpine-x64"
                FilePrefix = "vscode-cli-alpine-x64"
                Kind       = "cli"
                Label      = "VS Code CLI (Alpine x64)"
            }
        }
        "alpine-arm64" {
            return @{
                Segment    = "cli-alpine-arm64"
                FilePrefix = "vscode-cli-alpine-arm64"
                Kind       = "cli"
                Label      = "VS Code CLI (Alpine ARM64)"
            }
        }
        "cli-alpine-x64" {
            return @{
                Segment    = "cli-alpine-x64"
                FilePrefix = "vscode-cli-alpine-x64"
                Kind       = "cli"
                Label      = "VS Code CLI (Alpine x64)"
            }
        }
        "cli-alpine-arm64" {
            return @{
                Segment    = "cli-alpine-arm64"
                FilePrefix = "vscode-cli-alpine-arm64"
                Kind       = "cli"
                Label      = "VS Code CLI (Alpine ARM64)"
            }
        }
        default {
            # Allow callers to pass explicit segments starting with server-/cli-
            if ($p -like "server-*") {
                $suffix = $p.Substring("server-".Length)
                return @{
                    Segment    = $p
                    FilePrefix = "vscode-server-$suffix"
                    Kind       = "server"
                    Label      = "VS Code Server ($suffix)"
                }
            }
            elseif ($p -like "cli-*") {
                $suffix = $p.Substring("cli-".Length)
                return @{
                    Segment    = $p
                    FilePrefix = "vscode-cli-$suffix"
                    Kind       = "cli"
                    Label      = "VS Code CLI ($suffix)"
                }
            }

            Write-Host "`nERROR: Unsupported platform '$PlatformInput'." -ForegroundColor Red
            Write-Host "Supported examples:" -ForegroundColor Red
            Write-Host "  linux-x64, linux-arm64, server-linux-x64, server-linux-arm64" -ForegroundColor Red
            Write-Host "  alpine-x64, alpine-arm64, cli-alpine-x64, cli-alpine-arm64" -ForegroundColor Red
            return $null
        }
    }
}

$platformInfo = Resolve-CodeServerPlatform -PlatformInput $Platform
if ($null -eq $platformInfo) {
    exit 1
}

Write-Host "`nResolved platform segment : $($platformInfo.Segment)" -ForegroundColor Green
Write-Host "Component type            : $($platformInfo.Kind)" -ForegroundColor Green

# Resolve VS Code version and commit
$versionInfo = Get-VSCodeVersionInfo -RequestedVersion $TargetCodeVersion
if ($null -eq $versionInfo -or [string]::IsNullOrEmpty($versionInfo.Commit)) {
    Write-Host "ERROR: Could not determine VS Code commit hash; aborting." -ForegroundColor Red
    exit 1
}

$commitHash = $versionInfo.Commit
$resolvedVersion = $versionInfo.Version

# Build download URL and output filename
$segment = $platformInfo.Segment
$filePrefix = $platformInfo.FilePrefix
$label = $platformInfo.Label

$downloadUrl = "https://update.code.visualstudio.com/commit:$commitHash/$segment/stable"
$outputFileName = "$filePrefix-$commitHash.tar.gz"
$outputPath = Join-Path $OutputDir $outputFileName

Write-Host "`nPreparing to download component..." -ForegroundColor Cyan
Write-Host "  VS Code version : $resolvedVersion" -ForegroundColor Cyan
Write-Host "  Commit hash     : $commitHash" -ForegroundColor Cyan
Write-Host "  Segment         : $segment" -ForegroundColor Cyan
Write-Host "  Description     : $label" -ForegroundColor Cyan
Write-Host "  Output file     : $outputPath`n" -ForegroundColor Cyan

$description = "$label for commit $commitHash"
$success = Download-File -Url $downloadUrl -OutputPath $outputPath -Description $description

if ($success) {
    Write-Host "`n========================================" -ForegroundColor Green
    Write-Host "Download Complete!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "`nTarball location:" -ForegroundColor Cyan
    Write-Host "  $outputPath" -ForegroundColor White
    exit 0
}
else {
    Write-Host "`n========================================" -ForegroundColor Red
    Write-Host "Download Failed!" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    exit 1
}
