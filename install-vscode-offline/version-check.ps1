<#
.SYNOPSIS
    Check VS Code version and commit hash on local and remote systems.

.DESCRIPTION
    Utility script to verify VS Code versions and commit hashes to ensure
    compatibility between client and server installations.

.PARAMETER CheckLocal
    Check local VS Code installation on this Windows machine.

.PARAMETER CheckRemote
    Check VS Code Server installation on remote Linux host.

.PARAMETER SshHost
    SSH target for remote check (required if -CheckRemote is used).

.EXAMPLE
    .\version-check.ps1 -CheckLocal
    
.EXAMPLE
    .\version-check.ps1 -CheckRemote -SshHost "user@server"
    
.EXAMPLE
    .\version-check.ps1 -CheckLocal -CheckRemote -SshHost "user@server"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [switch]$CheckLocal,
    
    [Parameter(Mandatory=$false)]
    [switch]$CheckRemote,
    
    [Parameter(Mandatory=$false)]
    [string]$SshHost = $null
)

# If no flags specified, check local by default
if (-not $CheckLocal -and -not $CheckRemote) {
    $CheckLocal = $true
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "VS Code Version Checker" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Check local installation
if ($CheckLocal) {
    Write-Host "Local VS Code Installation:" -ForegroundColor Yellow
    Write-Host "─────────────────────────────" -ForegroundColor Yellow
    
    try {
        # Check if code is available
        $versionOutput = & code --version 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            $lines = $versionOutput -split "`n"
            if ($lines.Count -ge 3) {
                $version = $lines[0].Trim()
                $commit = $lines[1].Trim()
                $arch = $lines[2].Trim()
                
                Write-Host "  Version: $version" -ForegroundColor Green
                Write-Host "  Commit:  $commit" -ForegroundColor Green
                Write-Host "  Arch:    $arch" -ForegroundColor Green
                
                # Show download URLs for this version
                Write-Host "`n  Server Download URLs:" -ForegroundColor Cyan
                Write-Host "    x64:   https://update.code.visualstudio.com/commit:$commit/server-linux-x64/stable" -ForegroundColor White
                Write-Host "    ARM64: https://update.code.visualstudio.com/commit:$commit/server-linux-arm64/stable" -ForegroundColor White
            }
            else {
                Write-Host "  Unexpected version output format" -ForegroundColor Yellow
                Write-Host $versionOutput
            }
        }
        else {
            Write-Host "  VS Code not found or not in PATH" -ForegroundColor Red
            Write-Host "  Install VS Code and ensure 'code' command is available" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "  ERROR: $_" -ForegroundColor Red
        Write-Host "  Is VS Code installed?" -ForegroundColor Yellow
    }
    
    Write-Host ""
}

# Check remote installation
if ($CheckRemote) {
    if ([string]::IsNullOrWhiteSpace($SshHost)) {
        Write-Host "ERROR: -SshHost parameter required for remote check" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "Remote VS Code Server Installation ($SshHost):" -ForegroundColor Yellow
    Write-Host "─────────────────────────────────────────────" -ForegroundColor Yellow
    
    try {
        # Check if SSH is available
        $null = & ssh -V 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "SSH client not found"
        }
        
        # Check remote VS Code Server installations
        $checkScript = @"
if [ -d "\$HOME/.vscode-server" ]; then
    echo "VS Code Server directory exists"
    echo ""
    
    # Check new layout
    if [ -d "\$HOME/.vscode-server/cli/servers" ]; then
        echo "Found servers (new layout):"
        for server_dir in \$HOME/.vscode-server/cli/servers/Stable-*/; do
            if [ -d "\$server_dir" ]; then
                commit=\$(basename \$(dirname "\$server_dir") | sed 's/Stable-//')
                if [ -f "\$server_dir/server/bin/code-server" ]; then
                    size=\$(du -sh "\$server_dir/server" 2>/dev/null | cut -f1)
                    echo "  • Commit: \$commit"
                    echo "    Path: \$server_dir/server"
                    echo "    Size: \$size"
                    echo "    Status: ✓ Valid"
                    
                    # Try to get version
                    version=\$("\$server_dir/server/bin/code-server" --version 2>/dev/null | head -n1)
                    if [ ! -z "\$version" ]; then
                        echo "    Version: \$version"
                    fi
                    echo ""
                else
                    echo "  • Commit: \$commit"
                    echo "    Status: ✗ Invalid (code-server binary missing)"
                    echo ""
                fi
            fi
        done
    fi
    
    # Check old layout
    if [ -d "\$HOME/.vscode-server/bin" ]; then
        echo "Found servers (old layout):"
        for commit_dir in \$HOME/.vscode-server/bin/*/; do
            if [ -d "\$commit_dir" ]; then
                commit=\$(basename "\$commit_dir")
                if [ -f "\$commit_dir/bin/code-server" ]; then
                    size=\$(du -sh "\$commit_dir" 2>/dev/null | cut -f1)
                    echo "  • Commit: \$commit"
                    echo "    Path: \$commit_dir"
                    echo "    Size: \$size"
                    echo "    Status: ✓ Valid"
                    echo ""
                else
                    echo "  • Commit: \$commit"
                    echo "    Status: ✗ Invalid (code-server binary missing)"
                    echo ""
                fi
            fi
        done
    fi
    
    # Show total size
    total_size=\$(du -sh "\$HOME/.vscode-server" 2>/dev/null | cut -f1)
    echo "Total VS Code Server size: \$total_size"
else
    echo "VS Code Server not installed (directory does not exist)"
    echo "Expected location: \$HOME/.vscode-server"
fi
"@
        
        $remoteOutput = & ssh $SshHost $checkScript 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host $remoteOutput -ForegroundColor White
        }
        else {
            Write-Host "  ERROR: Failed to check remote installation" -ForegroundColor Red
            Write-Host "  SSH output: $remoteOutput" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "  ERROR: $_" -ForegroundColor Red
        
        if ($_.Exception.Message -like "*SSH client not found*") {
            Write-Host "  Install OpenSSH Client:" -ForegroundColor Yellow
            Write-Host "    Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0" -ForegroundColor Cyan
        }
    }
    
    Write-Host ""
}

# Compatibility check if both local and remote were checked
if ($CheckLocal -and $CheckRemote) {
    Write-Host "Compatibility Check:" -ForegroundColor Yellow
    Write-Host "────────────────────" -ForegroundColor Yellow
    Write-Host "Ensure the commit hash matches between local VS Code and remote VS Code Server." -ForegroundColor White
    Write-Host "If they don't match, Remote-SSH may attempt to download the correct version." -ForegroundColor White
    Write-Host "To prevent this, ensure 'remote.SSH.localServerDownload': 'always' is set." -ForegroundColor White
    Write-Host ""
}

Write-Host "========================================`n" -ForegroundColor Cyan
