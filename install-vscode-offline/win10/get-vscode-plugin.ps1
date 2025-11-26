<#
.SYNOPSIS
    Downloads a VS Code extension (.vsix) from Open VSX for offline installation.

.DESCRIPTION
    Downloads a specific VS Code extension, preferring the Open VSX Registry
    (via the `ovsx` CLI or HTTP API) and falling back to the Visual Studio
    Marketplace if the extension is not available on Open VSX.

    The extension is identified by its full identifier (publisher.extension).

    The downloaded file is saved as:
        <publisher>.<extension>-<version>.vsix
    or, when no version is specified:
        <publisher>.<extension>-latest.vsix

.PARAMETER PluginIdentifier
    Extension identifier in the form "publisher.extension"
    (e.g. "ms-python.python", "eamodio.gitlens").

.PARAMETER OutputDir
    Output directory where the .vsix file will be saved.
    Default: Current working directory (pwd)

.PARAMETER TargetVersion
    Specific extension version to download (e.g., "2025.11.2504").
    If not specified, downloads the latest version available (Open VSX preferred).

.PARAMETER Platform
    Target platform identifier for platform-specific extensions, following
    VS Code extension conventions (e.g. "win32-x64", "linux-x64",
    "linux-arm64", "darwin-x64", "darwin-arm64").
    Use "all" to download all available platforms (from Open VSX metadata
    or a known set for the VS Marketplace).
    If not specified, downloads the default/universal variant.

.EXAMPLE
    .\get-vscode-plugin.ps1 ms-python.python
    Downloads the latest "ms-python.python" extension to the current directory.

.EXAMPLE
    .\get-vscode-plugin.ps1 eamodio.gitlens -OutputDir "C:\Temp\vscode-extensions"
    Downloads the latest "eamodio.gitlens" extension to C:\Temp\vscode-extensions.

.EXAMPLE
    .\get-vscode-plugin.ps1 saoudrizwan.claude-dev -TargetVersion "3.38.2"
    Downloads version 3.38.2 of "saoudrizwan.claude-dev" to the current directory.

.EXAMPLE
    .\get-vscode-plugin.ps1 JanekWinkler.vscode-owl-ms -TargetVersion "0.8.0" -Platform "linux-x64"
    Downloads the Linux x64 build of a platform-specific extension from Open VSX.

.EXAMPLE
    .\get-vscode-plugin.ps1 JanekWinkler.vscode-owl-ms -TargetVersion "0.8.0" -Platform "all"
    Downloads all platform builds (linux-x64, win32-x64, darwin-x64, darwin-arm64)
    for the given version from Open VSX.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$PluginIdentifier,

    [Parameter(Mandatory = $false)]
    [string]$OutputDir = (Get-Location).Path,

    [Parameter(Mandatory = $false)]
    [string]$TargetVersion = "",

    [Parameter(Mandatory = $false)]
    [string]$Platform = ""
)

$ErrorActionPreference = "Stop"

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "VS Code Extension Downloader (Open VSX)" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Validate plugin identifier format
if ([string]::IsNullOrWhiteSpace($PluginIdentifier)) {
    Write-Host "ERROR: PluginIdentifier is required." -ForegroundColor Red
    exit 1
}

if (-not $PluginIdentifier.Contains(".")) {
    Write-Host "ERROR: PluginIdentifier must be in the form 'publisher.extension' (e.g. 'ms-python.python')." -ForegroundColor Red
    exit 1
}

# Split into namespace (publisher) and extension name
$parts = $PluginIdentifier.Split(".", 2)
$Namespace = $parts[0]
$ExtensionName = $parts[1]

Write-Host "Extension ID : $PluginIdentifier" -ForegroundColor Cyan
if ([string]::IsNullOrEmpty($TargetVersion)) {
    Write-Host "Target version: latest" -ForegroundColor Cyan
} else {
    Write-Host "Target version: $TargetVersion" -ForegroundColor Cyan
}

if ([string]::IsNullOrEmpty($Platform)) {
    Write-Host "Platform       : default/universal" -ForegroundColor Cyan
} else {
    Write-Host "Platform       : $Platform" -ForegroundColor Cyan
}

# Create output directory if it doesn't exist
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
    Write-Host "Created output directory: $OutputDir" -ForegroundColor Green
}

# Resolve to absolute path
$OutputDir = (Resolve-Path $OutputDir).Path

# Determine output file name
if ([string]::IsNullOrEmpty($TargetVersion)) {
    $versionLabel = "latest"
} else {
    $versionLabel = $TargetVersion
}

# Default output filename; for platform-specific requests, append @platform
if ([string]::IsNullOrEmpty($Platform) -or $Platform -eq "all") {
    $vsixFileName = "$PluginIdentifier-$versionLabel.vsix"
} else {
    $vsixFileName = "$PluginIdentifier-$versionLabel@$Platform.vsix"
}
$outputPath = Join-Path $OutputDir $vsixFileName

Write-Host "`nOutput directory:" -ForegroundColor Cyan
Write-Host "  $OutputDir" -ForegroundColor White
Write-Host "Output file:" -ForegroundColor Cyan
Write-Host "  $outputPath`n" -ForegroundColor White

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
            } else {
                Write-Host "`n  ERROR: Download incomplete (empty file)" -ForegroundColor Red
                Remove-Item $OutputPath -Force -ErrorAction SilentlyContinue
                return $false
            }
        } else {
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

# Try to use ovsx CLI first, if available
function Try-Download-WithOvsx {
    param(
        [string]$PluginIdentifier,
        [string]$OutputPath,
        [string]$TargetVersion
    )

    $ovsx = Get-Command ovsx -ErrorAction SilentlyContinue
    if (-not $ovsx) {
        Write-Host "ovsx CLI not found on PATH, skipping ovsx path." -ForegroundColor Yellow
        return $false
    }

    $ovsxPath = $ovsx.Source
    if (-not $ovsxPath) {
        $ovsxPath = $ovsx.Path
    }

    Write-Host "`nAttempting download via ovsx CLI..." -ForegroundColor Cyan
    Write-Host "  ovsx executable: $ovsxPath" -ForegroundColor White

    $arguments = @("get", $PluginIdentifier, "-o", $OutputPath)
    if (-not [string]::IsNullOrEmpty($TargetVersion)) {
        # ovsx uses --versionRange/-v to select a version
        $arguments += @("--versionRange", $TargetVersion)
    }

    try {
        & $ovsxPath @arguments
        $exitCode = $LASTEXITCODE

        if ($exitCode -ne 0) {
            Write-Host "  ovsx exited with code $exitCode, will try HTTP fallback." -ForegroundColor Yellow
            if (Test-Path $OutputPath) {
                Remove-Item $OutputPath -Force -ErrorAction SilentlyContinue
            }
            return $false
        }

        if (Test-Path $OutputPath) {
            $fileSize = (Get-Item $OutputPath).Length / 1MB
            if ($fileSize -gt 0) {
                Write-Host "  Downloaded via ovsx: $([math]::Round($fileSize, 2)) MB" -ForegroundColor Green
                return $true
            } else {
                Write-Host "  WARNING: File downloaded via ovsx is empty, removing and falling back." -ForegroundColor Yellow
                Remove-Item $OutputPath -Force -ErrorAction SilentlyContinue
                return $false
            }
        } else {
            Write-Host "  WARNING: ovsx completed but output file not found, falling back." -ForegroundColor Yellow
            return $false
        }
    }
    catch {
        Write-Host "  WARNING: ovsx download failed: $($_.Exception.Message)" -ForegroundColor Yellow
        if (Test-Path $OutputPath) {
            Remove-Item $OutputPath -Force -ErrorAction SilentlyContinue
        }
        return $false
    }
}

# Fallback: use Open VSX HTTP API directly
function Download-FromOpenVsxApi {
    param(
        [string]$Namespace,
        [string]$ExtensionName,
        [string]$TargetVersion,
        [string]$OutputPath,
        [string]$Platform
    )

    Write-Host "`nAttempting download via Open VSX HTTP API..." -ForegroundColor Cyan

    # Build metadata URL
    if ([string]::IsNullOrEmpty($TargetVersion)) {
        # Latest version metadata
        $metaUrl = "https://open-vsx.org/api/$Namespace/$ExtensionName"
    } else {
        # Specific version metadata
        $metaUrl = "https://open-vsx.org/api/$Namespace/$ExtensionName/$TargetVersion"
    }

    Write-Host "  Metadata URL: $metaUrl" -ForegroundColor White

    try {
        $metaResponse = Invoke-WebRequest -Uri $metaUrl -UseBasicParsing
    }
    catch {
        Write-Host "  ERROR: Failed to fetch metadata from Open VSX: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }

    if (-not $metaResponse -or -not $metaResponse.Content) {
        Write-Host "  ERROR: Empty metadata response from Open VSX." -ForegroundColor Red
        return $false
    }

    try {
        $meta = $metaResponse.Content | ConvertFrom-Json
    }
    catch {
        Write-Host "  ERROR: Failed to parse Open VSX metadata JSON: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }

    $outputDir = Split-Path -Parent $OutputPath
    $metaVersion = $meta.version

    # Helper to resolve a default download URL (for universal/default case)
    function Get-DefaultDownloadUrl {
        param($MetaObject)

        $downloadUrlInner = $null

        if ($MetaObject.files -and $MetaObject.files.download) {
            $downloadUrlInner = $MetaObject.files.download
        }
        elseif ($MetaObject.downloads) {
            if ($MetaObject.downloads.universal) {
                $downloadUrlInner = $MetaObject.downloads.universal
            }
            else {
                $downloadPropInner = $MetaObject.downloads.PSObject.Properties | Select-Object -First 1
                if ($downloadPropInner) {
                    $downloadUrlInner = $downloadPropInner.Value
                }
            }
        }

        return $downloadUrlInner
    }

    # No platform specified: behave as before and download the default/universal variant
    if ([string]::IsNullOrEmpty($Platform)) {
        $downloadUrl = Get-DefaultDownloadUrl -MetaObject $meta

        if (-not $downloadUrl) {
            Write-Host "  ERROR: No downloadable VSIX URL found in Open VSX metadata." -ForegroundColor Red
            return $false
        }

        Write-Host "  Resolved VSIX URL: $downloadUrl" -ForegroundColor White
        return Download-File -Url $downloadUrl -OutputPath $OutputPath -Description "VS Code extension $PluginIdentifier"
    }

    # Platform-specific handling
    if ($Platform -eq "all") {
        if (-not $meta.downloads) {
            Write-Host "  WARNING: No platform-specific 'downloads' map found on Open VSX; falling back to default download." -ForegroundColor Yellow
            $downloadUrl = Get-DefaultDownloadUrl -MetaObject $meta
            if (-not $downloadUrl) {
                Write-Host "  ERROR: No downloadable VSIX URL found in Open VSX metadata." -ForegroundColor Red
                return $false
            }

            Write-Host "  Resolved VSIX URL: $downloadUrl" -ForegroundColor White
            return Download-File -Url $downloadUrl -OutputPath $OutputPath -Description "VS Code extension $PluginIdentifier"
        }

        $allSucceeded = $true
        $platformProps = $meta.downloads.PSObject.Properties
        Write-Host "  Found platforms on Open VSX: $($platformProps.Name -join ', ')" -ForegroundColor Cyan

        foreach ($entry in $platformProps) {
            $platName = $entry.Name
            $url = $entry.Value
            if (-not $url) {
                continue
            }

            try {
                $uri = [System.Uri]$url
                $fileName = [System.IO.Path]::GetFileName($uri.AbsolutePath)
            }
            catch {
                $fileName = ""
            }

            if ([string]::IsNullOrEmpty($fileName)) {
                $label = if ([string]::IsNullOrEmpty($TargetVersion)) { $metaVersion } else { $TargetVersion }
                $fileName = "$PluginIdentifier-$label@$platName.vsix"
            }

            $destPath = Join-Path $outputDir $fileName
            $desc = "VS Code extension $PluginIdentifier ($platName)"
            $ok = Download-File -Url $url -OutputPath $destPath -Description $desc
            if (-not $ok) {
                $allSucceeded = $false
            }
        }

        return $allSucceeded
    }
    else {
        # Single, specific platform requested
        if ($meta.downloads) {
            $platformProp = $meta.downloads.PSObject.Properties |
                Where-Object { $_.Name -ieq $Platform } |
                Select-Object -First 1

            if (-not $platformProp) {
                $available = $meta.downloads.PSObject.Properties.Name -join ", "
                Write-Host "  ERROR: Platform '$Platform' not found in Open VSX metadata. Available platforms: $available" -ForegroundColor Red
                return $false
            }

            $url = $platformProp.Value

            try {
                $uri = [System.Uri]$url
                $fileName = [System.IO.Path]::GetFileName($uri.AbsolutePath)
            }
            catch {
                $fileName = ""
            }

            if ([string]::IsNullOrEmpty($fileName)) {
                $label = if ([string]::IsNullOrEmpty($TargetVersion)) { $metaVersion } else { $TargetVersion }
                $fileName = "$PluginIdentifier-$label@$($platformProp.Name).vsix"
            }

            $destPath = Join-Path $outputDir $fileName
            $desc = "VS Code extension $PluginIdentifier ($($platformProp.Name))"
            return Download-File -Url $url -OutputPath $destPath -Description $desc
        }

        Write-Host "  WARNING: Extension has no platform-specific 'downloads' map on Open VSX; using default download." -ForegroundColor Yellow
        $downloadUrl = Get-DefaultDownloadUrl -MetaObject $meta

        if (-not $downloadUrl) {
            Write-Host "  ERROR: No downloadable VSIX URL found in Open VSX metadata." -ForegroundColor Red
            return $false
        }

        Write-Host "  Resolved VSIX URL: $downloadUrl" -ForegroundColor White
        return Download-File -Url $downloadUrl -OutputPath $OutputPath -Description "VS Code extension $PluginIdentifier"
    }

    # Should not reach here
    return $false
}

# Final fallback: download from the Visual Studio Marketplace vspackage endpoint
function Download-FromVsMarketplace {
    param(
        [string]$Namespace,
        [string]$ExtensionName,
        [string]$TargetVersion,
        [string]$OutputPath,
        [string]$Platform
    )

    Write-Host "`nAttempting download via Visual Studio Marketplace..." -ForegroundColor Cyan

    $publisher = $Namespace
    $extension = $ExtensionName

    $versionSegment = if ([string]::IsNullOrEmpty($TargetVersion)) { "latest" } else { $TargetVersion }
    $baseUrl = "https://marketplace.visualstudio.com/_apis/public/gallery/publishers/$publisher/vsextensions/$extension/$versionSegment/vspackage"

    $outputDir = Split-Path -Parent $OutputPath
    $versionLabel = if ([string]::IsNullOrEmpty($TargetVersion)) { "latest" } else { $TargetVersion }

    if ([string]::IsNullOrEmpty($Platform)) {
        $vsMarketUrl = $baseUrl
        Write-Host "  Marketplace URL: $vsMarketUrl" -ForegroundColor White
        return Download-File -Url $vsMarketUrl -OutputPath $OutputPath -Description "VS Code extension $PluginIdentifier (VS Marketplace)"
    }

    if ($Platform -eq "all") {
        # Known VS Code target platforms for marketplace-hosted extensions
        $knownPlatforms = @(
            "win32-x64",
            "win32-arm64",
            "linux-x64",
            "linux-arm64",
            "linux-armhf",
            "alpine-x64",
            "alpine-arm64",
            "darwin-x64",
            "darwin-arm64"
        )

        Write-Host "  Attempting to download from VS Marketplace for all known target platforms..." -ForegroundColor Cyan
        $anySuccess = $false

        foreach ($plat in $knownPlatforms) {
            $vsMarketUrl = $baseUrl + "?targetPlatform=" + $plat
            $fileName = "$publisher.$extension-$versionLabel@$plat.vsix"
            $destPath = Join-Path $outputDir $fileName
            Write-Host "  Marketplace URL ($plat): $vsMarketUrl" -ForegroundColor White
            $ok = Download-File -Url $vsMarketUrl -OutputPath $destPath -Description "VS Code extension $PluginIdentifier ($plat, VS Marketplace)"
            if ($ok) {
                $anySuccess = $true
            }
        }

        if (-not $anySuccess) {
            Write-Host "  ERROR: Failed to download any platform from VS Marketplace." -ForegroundColor Red
        }

        return $anySuccess
    }
    else {
        $vsMarketUrl = $baseUrl + "?targetPlatform=" + $Platform
        Write-Host "  Marketplace URL: $vsMarketUrl" -ForegroundColor White

        # If OutputPath already has a platform-specific name, keep it.
        # Otherwise, derive a file name that includes the platform.
        $destPath = $OutputPath
        if ([string]::IsNullOrEmpty($destPath)) {
            $fileName = "$publisher.$extension-$versionLabel@$Platform.vsix"
            $destPath = Join-Path $outputDir $fileName
        }

        return Download-File -Url $vsMarketUrl -OutputPath $destPath -Description "VS Code extension $PluginIdentifier ($Platform, VS Marketplace)"
    }
}

# Main download flow
$success = $false

# 1) Try ovsx first (if available and no platform override)
if ([string]::IsNullOrEmpty($Platform)) {
    $success = Try-Download-WithOvsx -PluginIdentifier $PluginIdentifier -OutputPath $outputPath -TargetVersion $TargetVersion
} else {
    Write-Host "`nSkipping ovsx CLI because -Platform was specified; using registry/marketplace APIs directly." -ForegroundColor Yellow
}

# 2) If ovsx is not available or fails, fall back to Open VSX HTTP API
if (-not $success) {
    $success = Download-FromOpenVsxApi -Namespace $Namespace -ExtensionName $ExtensionName -TargetVersion $TargetVersion -OutputPath $outputPath -Platform $Platform
}

# 3) If Open VSX also fails (for example, extension not published there),
#    fall back to the Visual Studio Marketplace vspackage endpoint.
if (-not $success) {
    $success = Download-FromVsMarketplace -Namespace $Namespace -ExtensionName $ExtensionName -TargetVersion $TargetVersion -OutputPath $outputPath -Platform $Platform
}

if ($success) {
    Write-Host "`n========================================" -ForegroundColor Green
    Write-Host "Extension Download Complete!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    if ($Platform -eq "all") {
        Write-Host "`nVSIX files downloaded to directory:" -ForegroundColor Cyan
        Write-Host "  $OutputDir" -ForegroundColor White
    }
    else {
        Write-Host "`nVSIX location:" -ForegroundColor Cyan
        Write-Host "  $outputPath" -ForegroundColor White
    }
    exit 0
} else {
    Write-Host "`n========================================" -ForegroundColor Red
    Write-Host "Extension Download Failed!" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    exit 1
}
