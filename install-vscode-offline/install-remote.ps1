<#
.SYNOPSIS
    Installs VS Code Server on remote Linux host from offline package.

.DESCRIPTION
    This script automates the deployment of VS Code Server to a remote Linux host
    in an air-gapped environment. It copies the server tarball via SSH/SCP and
    extracts it to the correct location on the remote host.

.PARAMETER OfflinePackageDir
    Directory containing the downloaded VS Code offline package.

.PARAMETER SshHost
    SSH target in the format "user@hostname" or an alias from SSH config.

.PARAMETER SshPassword
    Optional SSH password for authentication. If not provided and key-based
    auth is not configured, you'll be prompted interactively.

.PARAMETER Arch
    Target Linux architecture: "x64" (default) or "arm64".
    If not specified, the script will try to detect it from the remote host.

.PARAMETER SshPort
    SSH port number. Default: 22

.PARAMETER SkipHostKeyCheck
    Skip SSH host key verification (not recommended for production).

.EXAMPLE
    .\install-remote.ps1 -OfflinePackageDir ".\vscode-package" -SshHost "user@192.168.1.100"
    
.EXAMPLE
    .\install-remote.ps1 -OfflinePackageDir "C:\vscode-package" -SshHost "myserver" -SshPassword "mypass" -Arch "x64"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$OfflinePackageDir,
    
    [Parameter(Mandatory=$true)]
    [string]$SshHost,
    
    [Parameter(Mandatory=$false)]
    [Alias("SshPw")]
    [string]$SshPassword = $null,
    
    [Parameter(Mandatory=$false)]
    [ValidateSet("x64", "arm64", "auto")]
    [string]$Arch = "auto",
    
    [Parameter(Mandatory=$false)]
    [int]$SshPort = 22,
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipHostKeyCheck
)

$ErrorActionPreference = "Stop"

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "VS Code Server Remote Installer" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Validate package directory
if (-not (Test-Path $OfflinePackageDir)) {
    Write-Host "ERROR: Package directory not found: $OfflinePackageDir" -ForegroundColor Red
    exit 1
}

$OfflinePackageDir = Resolve-Path $OfflinePackageDir

# Check for metadata file
$metadataPath = Join-Path $OfflinePackageDir "package-info.json"
if (Test-Path $metadataPath) {
    $metadata = Get-Content $metadataPath | ConvertFrom-Json
    Write-Host "Package Information:" -ForegroundColor Cyan
    Write-Host "  VS Code Version: $($metadata.VSCodeVersion)" -ForegroundColor White
    Write-Host "  Commit Hash: $($metadata.CommitHash)" -ForegroundColor White
    Write-Host "  Downloaded: $($metadata.DownloadDate)" -ForegroundColor White
    $commitHash = $metadata.CommitHash
}
else {
    Write-Host "WARNING: package-info.json not found. Will try to detect commit hash from filenames." -ForegroundColor Yellow
    $commitHash = $null
}

Write-Host ""

# Function to execute SSH command
function Invoke-SshCommand {
    param(
        [string]$Command,
        [string]$HostTarget,
        [int]$Port = 22,
        [string]$Password = $null,
        [switch]$SkipHostKeyCheck,
        [string]$Description = ""
    )
    
    if ($Description) {
        Write-Host "Executing: $Description" -ForegroundColor Yellow
    }
    
    # Build SSH command
    $sshArgs = @()
    
    if ($SkipHostKeyCheck) {
        $sshArgs += "-o", "StrictHostKeyChecking=no"
        $sshArgs += "-o", "UserKnownHostsFile=/dev/null"
    }
    
    if ($Port -ne 22) {
        $sshArgs += "-p", $Port
    }
    
    $sshArgs += $HostTarget
    $sshArgs += $Command
    
    try {
        if ($Password) {
            # Use password authentication with echo
            # Note: This is less secure. For production, use key-based auth.
            $passwordProcess = "echo '$Password' | "
            $fullCommand = "$passwordProcess ssh $($sshArgs -join ' ')"
            
            # Execute via cmd to handle piping
            $output = & cmd /c $fullCommand 2>&1
        }
        else {
            # Use OpenSSH directly (will use keys or prompt for password)
            $output = & ssh $sshArgs 2>&1
        }
        
        if ($LASTEXITCODE -ne 0) {
            throw "SSH command failed with exit code $LASTEXITCODE"
        }
        
        return $output
    }
    catch {
        Write-Host "  ERROR: $_" -ForegroundColor Red
        throw
    }
}

# Function to copy file via SCP
function Copy-ViaScp {
    param(
        [string]$LocalPath,
        [string]$RemotePath,
        [string]$HostTarget,
        [int]$Port = 22,
        [string]$Password = $null,
        [switch]$SkipHostKeyCheck,
        [string]$Description = ""
    )
    
    if ($Description) {
        Write-Host "Copying: $Description" -ForegroundColor Yellow
    }
    
    Write-Host "  Local: $LocalPath"
    Write-Host "  Remote: ${HostTarget}:${RemotePath}"
    
    # Build SCP command
    $scpArgs = @()
    
    if ($SkipHostKeyCheck) {
        $scpArgs += "-o", "StrictHostKeyChecking=no"
        $scpArgs += "-o", "UserKnownHostsFile=/dev/null"
    }
    
    if ($Port -ne 22) {
        $scpArgs += "-P", $Port
    }
    
    $scpArgs += $LocalPath
    $scpArgs += "${HostTarget}:${RemotePath}"
    
    try {
        if ($Password) {
            # For Windows, we'll use a workaround with plink if available, or prompt user
            Write-Host "  NOTE: Password authentication via SCP requires manual entry or key-based auth." -ForegroundColor Yellow
            Write-Host "  Attempting SCP (you may be prompted for password)..." -ForegroundColor Yellow
        }
        
        $scpOutput = & scp $scpArgs 2>&1
        
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  SCP output: $scpOutput" -ForegroundColor Red
            throw "SCP failed with exit code $LASTEXITCODE"
        }
        
        Write-Host "  Transfer complete" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "  ERROR: $_" -ForegroundColor Red
        throw
    }
}

# Check if SSH is available
try {
    $sshVersion = & ssh -V 2>&1
    Write-Host "Using SSH: $sshVersion" -ForegroundColor Green
}
catch {
    Write-Host "ERROR: SSH client not found. Please install OpenSSH for Windows." -ForegroundColor Red
    Write-Host "You can install it via: Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0" -ForegroundColor Yellow
    exit 1
}

Write-Host ""

# Detect remote architecture if needed
if ($Arch -eq "auto") {
    Write-Host "Detecting remote architecture..." -ForegroundColor Yellow
    try {
        $archOutput = Invoke-SshCommand -Command "uname -m" -HostTarget $SshHost -Port $SshPort -Password $SshPassword -SkipHostKeyCheck:$SkipHostKeyCheck
        $remoteMachine = $archOutput.Trim()
        
        if ($remoteMachine -eq "x86_64" -or $remoteMachine -eq "amd64") {
            $Arch = "x64"
        }
        elseif ($remoteMachine -eq "aarch64" -or $remoteMachine -eq "arm64") {
            $Arch = "arm64"
        }
        else {
            Write-Host "  WARNING: Unknown architecture '$remoteMachine', defaulting to x64" -ForegroundColor Yellow
            $Arch = "x64"
        }
        
        Write-Host "  Detected: $remoteMachine -> $Arch" -ForegroundColor Green
    }
    catch {
        Write-Host "  WARNING: Could not detect architecture, defaulting to x64" -ForegroundColor Yellow
        $Arch = "x64"
    }
}

Write-Host ""

# Find the server tarball
$serverTarball = $null
$serverFiles = Get-ChildItem -Path $OfflinePackageDir -Filter "vscode-server-linux-$Arch-*.tar.gz"

if ($serverFiles.Count -eq 0) {
    Write-Host "ERROR: No VS Code Server tarball found for architecture: $Arch" -ForegroundColor Red
    Write-Host "Expected file pattern: vscode-server-linux-$Arch-*.tar.gz" -ForegroundColor Yellow
    exit 1
}
elseif ($serverFiles.Count -gt 1) {
    Write-Host "WARNING: Multiple server tarballs found, using the first one:" -ForegroundColor Yellow
    $serverFiles | ForEach-Object { Write-Host "  - $($_.Name)" -ForegroundColor White }
    $serverTarball = $serverFiles[0]
}
else {
    $serverTarball = $serverFiles[0]
}

Write-Host "Using server tarball: $($serverTarball.Name)" -ForegroundColor Cyan

# Extract commit hash from filename if not available from metadata
if (-not $commitHash) {
    if ($serverTarball.Name -match "vscode-server-linux-$Arch-([a-f0-9]{40})\.tar\.gz") {
        $commitHash = $Matches[1]
        Write-Host "Extracted commit hash from filename: $commitHash" -ForegroundColor Green
    }
    else {
        Write-Host "ERROR: Could not determine commit hash from filename: $($serverTarball.Name)" -ForegroundColor Red
        Write-Host "Expected format: vscode-server-linux-$Arch-<40-char-commit-hash>.tar.gz" -ForegroundColor Yellow
        exit 1
    }
}

Write-Host ""

# Create temporary directory on remote
Write-Host "----------------------------------------" -ForegroundColor Cyan
Write-Host "Preparing remote host..." -ForegroundColor Cyan
Write-Host "----------------------------------------`n" -ForegroundColor Cyan

$remoteTempDir = "/tmp/vscode-server-install-$(Get-Date -Format 'yyyyMMddHHmmss')"
try {
    Invoke-SshCommand -Command "mkdir -p $remoteTempDir" -HostTarget $SshHost -Port $SshPort -Password $SshPassword -SkipHostKeyCheck:$SkipHostKeyCheck -Description "Creating temp directory"
    Write-Host "  Created: $remoteTempDir" -ForegroundColor Green
}
catch {
    Write-Host "ERROR: Failed to create temp directory on remote host" -ForegroundColor Red
    exit 1
}

Write-Host ""

# Copy tarball to remote
Write-Host "----------------------------------------" -ForegroundColor Cyan
Write-Host "Transferring files..." -ForegroundColor Cyan
Write-Host "----------------------------------------`n" -ForegroundColor Cyan

$remoteTarballPath = "$remoteTempDir/$($serverTarball.Name)"
try {
    Copy-ViaScp -LocalPath $serverTarball.FullName -RemotePath $remoteTarballPath -HostTarget $SshHost -Port $SshPort -Password $SshPassword -SkipHostKeyCheck:$SkipHostKeyCheck -Description "VS Code Server tarball"
}
catch {
    Write-Host "ERROR: Failed to copy tarball to remote host" -ForegroundColor Red
    # Cleanup
    Invoke-SshCommand -Command "rm -rf $remoteTempDir" -HostTarget $SshHost -Port $SshPort -Password $SshPassword -SkipHostKeyCheck:$SkipHostKeyCheck | Out-Null
    exit 1
}

Write-Host ""

# Extract and install on remote
Write-Host "----------------------------------------" -ForegroundColor Cyan
Write-Host "Installing VS Code Server..." -ForegroundColor Cyan
Write-Host "----------------------------------------`n" -ForegroundColor Cyan

$installScript = @"
set -e

COMMIT="$commitHash"
TARBALL="$remoteTarballPath"

echo "Installing VS Code Server..."
echo "  Commit: \$COMMIT"
echo "  Architecture: $Arch"

# Create the target directory (new layout for VS Code >= 1.82)
TARGET_DIR="\$HOME/.vscode-server/cli/servers/Stable-\$COMMIT/server"
echo "  Target: \$TARGET_DIR"

mkdir -p "\$TARGET_DIR"

# Extract tarball
echo "Extracting tarball..."
tar -xzf "\$TARBALL" --strip-components=1 -C "\$TARGET_DIR"

if [ \$? -eq 0 ]; then
    echo "Installation successful!"
    
    # Verify installation
    if [ -f "\$TARGET_DIR/bin/code-server" ]; then
        echo "VS Code Server binary found: \$TARGET_DIR/bin/code-server"
    else
        echo "WARNING: code-server binary not found at expected location"
    fi
    
    # Also create old-style symlink for backward compatibility
    OLD_DIR="\$HOME/.vscode-server/bin/\$COMMIT"
    if [ ! -d "\$OLD_DIR" ]; then
        mkdir -p "\$HOME/.vscode-server/bin"
        ln -sf "\$TARGET_DIR" "\$OLD_DIR"
        echo "Created backward-compatibility symlink: \$OLD_DIR"
    fi
    
    # Cleanup
    rm -f "\$TARBALL"
    echo "Cleaned up temporary files"
    
    exit 0
else
    echo "ERROR: Failed to extract tarball"
    exit 1
fi
"@

try {
    $output = Invoke-SshCommand -Command $installScript -HostTarget $SshHost -Port $SshPort -Password $SshPassword -SkipHostKeyCheck:$SkipHostKeyCheck -Description "Installation script"
    Write-Host $output -ForegroundColor White
    Write-Host ""
}
catch {
    Write-Host "ERROR: Installation failed" -ForegroundColor Red
    # Cleanup
    Invoke-SshCommand -Command "rm -rf $remoteTempDir" -HostTarget $SshHost -Port $SshPort -Password $SshPassword -SkipHostKeyCheck:$SkipHostKeyCheck | Out-Null
    exit 1
}

# Cleanup temp directory
try {
    Invoke-SshCommand -Command "rm -rf $remoteTempDir" -HostTarget $SshHost -Port $SshPort -Password $SshPassword -SkipHostKeyCheck:$SkipHostKeyCheck | Out-Null
}
catch {
    Write-Host "WARNING: Could not cleanup temp directory: $remoteTempDir" -ForegroundColor Yellow
}

# Final verification
Write-Host "----------------------------------------" -ForegroundColor Cyan
Write-Host "Verifying installation..." -ForegroundColor Cyan
Write-Host "----------------------------------------`n" -ForegroundColor Cyan

try {
    $verifyScript = @"
if [ -d "\$HOME/.vscode-server/cli/servers/Stable-$commitHash/server" ]; then
    echo "✓ VS Code Server directory exists"
    du -sh "\$HOME/.vscode-server/cli/servers/Stable-$commitHash/server" 2>/dev/null || true
    exit 0
else
    echo "✗ VS Code Server directory not found"
    exit 1
fi
"@
    $verifyOutput = Invoke-SshCommand -Command $verifyScript -HostTarget $SshHost -Port $SshPort -Password $SshPassword -SkipHostKeyCheck:$SkipHostKeyCheck
    Write-Host $verifyOutput -ForegroundColor Green
}
catch {
    Write-Host "WARNING: Could not verify installation" -ForegroundColor Yellow
}

Write-Host ""

# Summary
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Installation Complete!" -ForegroundColor Green
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "VS Code Server has been installed on: $SshHost" -ForegroundColor White
Write-Host "Commit: $commitHash" -ForegroundColor White
Write-Host "Architecture: $Arch" -ForegroundColor White
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "1. On your Windows machine, ensure Remote-SSH extension is installed" -ForegroundColor White
Write-Host "2. Add to VS Code settings (JSON):" -ForegroundColor White
Write-Host '   "remote.SSH.localServerDownload": "always"' -ForegroundColor Yellow
Write-Host "3. Connect to $SshHost via Remote-SSH in VS Code" -ForegroundColor White
Write-Host ""
Write-Host "No internet connection required on either machine!" -ForegroundColor Green
Write-Host ""
