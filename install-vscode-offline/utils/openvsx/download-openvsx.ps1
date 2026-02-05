<#
.SYNOPSIS
    Downloads a VSIX extension from Open VSX Registry.

.DESCRIPTION
    Resolves the latest version (if not specified) and downloads the .vsix file.

.PARAMETER ExtensionId
    The ID of the extension in the format 'publisher.name' (e.g., 'redhat.java').

.PARAMETER Version
    Optional. The specific version to download. If omitted, downloads the latest.

.PARAMETER OutputDir
    Optional. Directory to save the file. Defaults to current directory.

.EXAMPLE
    .\download-openvsx.ps1 -ExtensionId "redhat.java"
    .\download-openvsx.ps1 -ExtensionId "redhat.java" -Version "0.65.0"
#>

param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$ExtensionId,
    
    [string]$Version,

    [string]$OutputDir = "."
)

# Parse Namespace and Name
if ($ExtensionId -notmatch '^[a-zA-Z0-9-]+\.[a-zA-Z0-9-]+$') {
    Write-Error "Invalid Extension ID format. Expected 'publisher.name' (e.g., 'redhat.java')."
    exit 1
}

$parts = $ExtensionId -split '\.'
$Namespace = $parts[0]
$Name = $parts[1]

# If version is not provided, fetch the latest one
if ([string]::IsNullOrWhiteSpace($Version)) {
    Write-Host "Fetching latest version info for $ExtensionId..." -ForegroundColor Cyan
    try {
        $metaUrl = "https://open-vsx.org/api/$Namespace/$Name"
        $meta = Invoke-RestMethod -Uri $metaUrl -ErrorAction Stop
        $Version = $meta.version
        Write-Host "Latest version is: $Version" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to get extension metadata. Check if the ID '$ExtensionId' is correct."
        exit 1
    }
}

# Construct Download URL
# Format: https://open-vsx.org/api/<namespace>.<name>/<version>/file/<namespace>.<name>-<version>.vsix
$DownloadUrl = "https://open-vsx.org/api/$Namespace.$Name/$Version/file/$Namespace.$Name-$Version.vsix"
$FileName = "$Namespace.$Name-$Version.vsix"
$OutputPath = Join-Path $OutputDir $FileName

# Create output directory if it doesn't exist
if (!(Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
}

try {
    Write-Host "Downloading $FileName from Open VSX..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $OutputPath -ErrorAction Stop
    Write-Host "Successfully downloaded to: $OutputPath" -ForegroundColor Green
}
catch {
    Write-Error "Failed to download file. Status code: $_.Exception.Response.StatusCode. The version '$Version' might not exist or the URL format has changed."
}
