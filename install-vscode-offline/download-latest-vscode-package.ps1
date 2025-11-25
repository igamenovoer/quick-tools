<#
.SYNOPSIS
    Downloads VS Code, Remote-SSH extension, and VS Code Server for offline installation.

.DESCRIPTION
    This script downloads all necessary components to install VS Code with Remote-SSH
    in an air-gapped environment. It fetches the VS Code installer, Remote-SSH extension,
    and VS Code Server tarballs for both x64 and ARM64 Linux architectures.

.PARAMETER Output
    Output directory where downloaded files will be saved. 
    Default: (pwd)/vscode-package

.PARAMETER Version
    Specific VS Code version to download (e.g., "1.105.1").
    If not specified, downloads the latest stable version.

.EXAMPLE
    .\download-latest-vscode-package.ps1
    Downloads latest version to ./vscode-package

.EXAMPLE
    .\download-latest-vscode-package.ps1 -Output "C:\Temp\vscode" -Version "1.105.1"
    Downloads version 1.105.1 to C:\Temp\vscode
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [Alias("o")]
    [string]$Output = (Join-Path (Get-Location) "vscode-package"),
    
    [Parameter(Mandatory=$false)]
    [string]$Version = $null
)

$ErrorActionPreference = "Stop"

# Create output directory
if (-not (Test-Path $Output)) {
    New-Item -ItemType Directory -Path $Output -Force | Out-Null
    Write-Host "Created output directory: $Output" -ForegroundColor Green
}

# Resolve to absolute path
$Output = Resolve-Path $Output

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "VS Code Offline Package Downloader" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Function to download file with progress
function Download-File {
    param(
        [string]$Url,
        [string]$OutputPath,
        [string]$Description
    )
    
    Write-Host "Downloading: $Description" -ForegroundColor Yellow
    Write-Host "  URL: $Url"
    Write-Host "  Output: $OutputPath"
    
    try {
        # Use WebClient for progress (Invoke-WebRequest can be slow for large files)
        $webClient = New-Object System.Net.WebClient
        $webClient.DownloadFile($Url, $OutputPath)
        
        $fileSize = (Get-Item $OutputPath).Length / 1MB
        Write-Host "  Downloaded: $([math]::Round($fileSize, 2)) MB" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "  ERROR: Failed to download - $_" -ForegroundColor Red
        return $false
    }
}

# Function to download a VSIX, preferring Open VSX (ovsx) when available,
# and falling back to the Visual Studio Marketplace vspackage URL.
function Download-Vsix {
    param(
        [string]$Namespace,      # e.g. 'ms-vscode-remote'
        [string]$ExtensionName,  # e.g. 'remote-ssh'
        [string]$OutputPath,
        [string]$MarketplaceUrl, # vspackage URL as fallback
        [string]$Description
    )

    $ovsx = Get-Command ovsx -ErrorAction SilentlyContinue
    if ($ovsx) {
        $id = \"$Namespace.$ExtensionName\"
        Write-Host \"Downloading (ovsx): $Description\" -ForegroundColor Yellow
        Write-Host \"  ID    : $id\"
        Write-Host \"  Output: $OutputPath\"
        try {
            ovsx get $id -o $OutputPath
            $fileSize = (Get-Item $OutputPath).Length / 1MB
            Write-Host \"  Downloaded via ovsx: $([math]::Round($fileSize, 2)) MB\" -ForegroundColor Green
            return $true
        }
        catch {
            Write-Host \"  WARNING: ovsx download failed, falling back to Marketplace: $_\" -ForegroundColor Yellow
        }
    }

    # Fallback to original vspackage URL
    return Download-File -Url $MarketplaceUrl -OutputPath $OutputPath -Description $Description
}

# Function to get latest VS Code version info
function Get-LatestVSCodeVersion {
    Write-Host "Fetching latest VS Code version information..." -ForegroundColor Yellow
    
    try {
        # VS Code updates API endpoint
        $apiUrl = "https://update.code.visualstudio.com/api/update/win32-x64-user/stable/latest"
        $response = Invoke-RestMethod -Uri $apiUrl -Method Get
        
        return @{
            Version = $response.productVersion
            Commit = $response.version
            Timestamp = $response.timestamp
        }
    }
    catch {
        Write-Host "  WARNING: Could not fetch latest version info: $_" -ForegroundColor Yellow
        return $null
    }
}

# Get version and commit hash
$commitHash = $null
$vscodeVersion = $null

if ([string]::IsNullOrEmpty($Version)) {
    # Fetch latest version
    $versionInfo = Get-LatestVSCodeVersion
    if ($versionInfo) {
        $vscodeVersion = $versionInfo.Version
        $commitHash = $versionInfo.Commit
        Write-Host "Latest version: $vscodeVersion (Commit: $commitHash)" -ForegroundColor Green
    }
    else {
        Write-Host "Could not determine latest version. Please specify -Version parameter." -ForegroundColor Red
        exit 1
    }
}
else {
    $vscodeVersion = $Version
    Write-Host "Using specified version: $vscodeVersion" -ForegroundColor Green
    
    # For specific version, we need to derive the commit hash
    # Try to get it from the version-specific API
    try {
        $apiUrl = "https://update.code.visualstudio.com/api/update/win32-x64-user/stable/$vscodeVersion"
        $response = Invoke-RestMethod -Uri $apiUrl -Method Get
        $commitHash = $response.version
        Write-Host "Commit hash: $commitHash" -ForegroundColor Green
    }
    catch {
        Write-Host "  WARNING: Could not fetch commit hash for version $vscodeVersion" -ForegroundColor Yellow
        Write-Host "  You may need to obtain the commit hash manually from 'code --version' after installing." -ForegroundColor Yellow
    }
}

Write-Host "`n----------------------------------------" -ForegroundColor Cyan
Write-Host "Downloading Components" -ForegroundColor Cyan
Write-Host "----------------------------------------`n" -ForegroundColor Cyan

$downloads = @()
$downloadResults = @()

# 1. VS Code Windows Installer (User)
$vscodeInstallerUrl = "https://update.code.visualstudio.com/latest/win32-x64-user/stable"
if (-not [string]::IsNullOrEmpty($vscodeVersion) -and $vscodeVersion -ne "latest") {
    $vscodeInstallerUrl = "https://update.code.visualstudio.com/$vscodeVersion/win32-x64-user/stable"
}
$vscodeInstallerPath = Join-Path $Output "VSCodeUserSetup-x64-$vscodeVersion.exe"
$downloads += @{
    Url = $vscodeInstallerUrl
    Path = $vscodeInstallerPath
    Description = "VS Code Windows Installer (x64, User)"
}

# 2. Remote-SSH Extension
$remoteSshExtUrl = "https://marketplace.visualstudio.com/_apis/public/gallery/publishers/ms-vscode-remote/vsextensions/remote-ssh/latest/vspackage"
$remoteSshExtPath = Join-Path $Output "ms-vscode-remote.remote-ssh-latest.vsix"
$downloads += @{
    Url = $remoteSshExtUrl
    Path = $remoteSshExtPath
    Description = "Remote-SSH Extension (.vsix)"
    Kind = "vsix-ms-vscode-remote.remote-ssh"
}

# 3. Remote-SSH: Editing Configuration Files Extension (optional but recommended)
$remoteSshEditUrl = "https://marketplace.visualstudio.com/_apis/public/gallery/publishers/ms-vscode-remote/vsextensions/remote-ssh-edit/latest/vspackage"
$remoteSshEditPath = Join-Path $Output "ms-vscode-remote.remote-ssh-edit-latest.vsix"
$downloads += @{
    Url = $remoteSshEditUrl
    Path = $remoteSshEditPath
    Description = "Remote-SSH: Editing Configuration Files Extension (.vsix)"
    Kind = "vsix-ms-vscode-remote.remote-ssh-edit"
}

# 4. VS Code Server - Linux x64
if ($commitHash) {
    $serverX64Url = "https://update.code.visualstudio.com/commit:$commitHash/server-linux-x64/stable"
    $serverX64Path = Join-Path $Output "vscode-server-linux-x64-$commitHash.tar.gz"
    $downloads += @{
        Url = $serverX64Url
        Path = $serverX64Path
        Description = "VS Code Server (Linux x64)"
    }

    # 5. VS Code Server - Linux ARM64
    $serverArm64Url = "https://update.code.visualstudio.com/commit:$commitHash/server-linux-arm64/stable"
    $serverArm64Path = Join-Path $Output "vscode-server-linux-arm64-$commitHash.tar.gz"
    $downloads += @{
        Url = $serverArm64Url
        Path = $serverArm64Path
        Description = "VS Code Server (Linux ARM64)"
    }
}
else {
    Write-Host "Skipping VS Code Server downloads (commit hash not available)" -ForegroundColor Yellow
}

# Download all components
foreach ($download in $downloads) {
    $kind = $download.Kind
    $result = $false

    if ($kind -eq "vsix-ms-vscode-remote.remote-ssh") {
        $result = Download-Vsix -Namespace "ms-vscode-remote" -ExtensionName "remote-ssh" `
            -OutputPath $download.Path -MarketplaceUrl $download.Url -Description $download.Description
    }
    elseif ($kind -eq "vsix-ms-vscode-remote.remote-ssh-edit") {
        $result = Download-Vsix -Namespace "ms-vscode-remote" -ExtensionName "remote-ssh-edit" `
            -OutputPath $download.Path -MarketplaceUrl $download.Url -Description $download.Description
    }
    else {
        $result = Download-File -Url $download.Url -OutputPath $download.Path -Description $download.Description
    }

    $downloadResults += @{
        Description = $download.Description
        Path = $download.Path
        Success = $result
    }
    Write-Host ""
}

# Create metadata file
Write-Host "----------------------------------------" -ForegroundColor Cyan
Write-Host "Creating metadata file..." -ForegroundColor Cyan

$metadata = @{
    DownloadDate = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    VSCodeVersion = $vscodeVersion
    CommitHash = $commitHash
    Components = @()
}

foreach ($result in $downloadResults) {
    if ($result.Success) {
        $fileInfo = Get-Item $result.Path
        $metadata.Components += @{
            Description = $result.Description
            Filename = $fileInfo.Name
            Size = $fileInfo.Length
            SizeMB = [math]::Round($fileInfo.Length / 1MB, 2)
        }
    }
}

$metadataPath = Join-Path $Output "package-info.json"
$metadata | ConvertTo-Json -Depth 10 | Out-File -FilePath $metadataPath -Encoding UTF8
Write-Host "Metadata saved to: $metadataPath" -ForegroundColor Green

# Create README
$readmePath = Join-Path $Output "README.txt"
$readmeContent = @"
VS Code Offline Installation Package
=====================================

Downloaded: $($metadata.DownloadDate)
VS Code Version: $vscodeVersion
Commit Hash: $commitHash

Contents:
---------
"@

foreach ($component in $metadata.Components) {
    $readmeContent += "`n- $($component.Filename) ($($component.SizeMB) MB) - $($component.Description)"
}

$readmeContent += @"


Installation Instructions:
--------------------------
1. Copy this entire directory to your offline Windows machine (A)

2. On Windows machine A:
   - Run the VSCodeUserSetup-x64-*.exe to install VS Code
   - Install Remote-SSH extension:
     code --install-extension ms-vscode-remote.remote-ssh-*.vsix
     code --install-extension ms-vscode-remote.remote-ssh-edit-*.vsix
   
3. Configure VS Code to use local server download:
   Add to VS Code settings (JSON):
   {
     "remote.SSH.localServerDownload": "always"
   }

4. Copy the appropriate VS Code Server tarball to your Linux machine (B):
   - For x86_64/amd64: vscode-server-linux-x64-*.tar.gz
   - For ARM64: vscode-server-linux-arm64-*.tar.gz

5. On Linux machine B, extract the server:
   COMMIT="$commitHash"
   ARCH="x64"  # or "arm64"
   
   mkdir -p ~/.vscode-server/cli/servers/Stable-`$COMMIT/server
   tar -xzf vscode-server-linux-`${ARCH}-`${COMMIT}.tar.gz \
       --strip-components=1 \
       -C ~/.vscode-server/cli/servers/Stable-`$COMMIT/server

6. Connect from VS Code on A to B via SSH

For automated installation, use the install-remote.ps1 script.
"@

$readmeContent | Out-File -FilePath $readmePath -Encoding UTF8
Write-Host "README saved to: $readmePath" -ForegroundColor Green

# Summary
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Download Summary" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

$successCount = ($downloadResults | Where-Object { $_.Success }).Count
$totalCount = $downloadResults.Count

Write-Host "Successfully downloaded: $successCount / $totalCount" -ForegroundColor $(if ($successCount -eq $totalCount) { "Green" } else { "Yellow" })
Write-Host "Package directory: $Output" -ForegroundColor Cyan

if ($successCount -lt $totalCount) {
    Write-Host "`nFailed downloads:" -ForegroundColor Red
    $downloadResults | Where-Object { -not $_.Success } | ForEach-Object {
        Write-Host "  - $($_.Description)" -ForegroundColor Red
    }
}

Write-Host "`nPackage ready for offline installation!" -ForegroundColor Green
Write-Host "Next step: Use install-remote.ps1 to deploy to remote Linux hosts.`n" -ForegroundColor Cyan
