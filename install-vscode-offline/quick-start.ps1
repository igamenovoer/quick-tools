<#
.SYNOPSIS
    Quick-start example for VS Code offline installation workflow.

.DESCRIPTION
    This script demonstrates the complete workflow for offline VS Code installation.
    It's intended as a template/example - customize for your environment.
#>

Write-Host @"

╔════════════════════════════════════════════════════════════════════╗
║                                                                    ║
║     VS Code Offline Installation - Quick Start Guide              ║
║                                                                    ║
╚════════════════════════════════════════════════════════════════════╝

This guide will help you set up VS Code with Remote-SSH in an air-gapped
environment. Follow the steps below:

STEP 1: Download Components (Internet-Connected Machine)
═══════════════════════════════════════════════════════════════════

Run on a machine with internet access:

    .\download-latest-vscode-package.ps1

Or specify custom output directory and version:

    .\download-latest-vscode-package.ps1 -Output "E:\usb\vscode" -Version "1.105.1"

This downloads:
  ✓ VS Code Windows Installer
  ✓ Remote-SSH Extensions
  ✓ VS Code Server (x64 & ARM64)


STEP 2: Transfer Package
═══════════════════════════════════════════════════════════════════

Copy the entire package directory to your offline Windows machine via:
  • USB drive
  • Secure file transfer
  • Physical media


STEP 3: Install VS Code Locally (Offline Windows Machine)
═══════════════════════════════════════════════════════════════════

Run the installer:

    cd C:\vscode-package
    .\VSCodeUserSetup-x64-*.exe

Install extensions:

    code --install-extension .\ms-vscode-remote.remote-ssh-*.vsix
    code --install-extension .\ms-vscode-remote.remote-ssh-edit-*.vsix


STEP 4: Configure VS Code Settings
═══════════════════════════════════════════════════════════════════

Open VS Code → Settings (Ctrl+,) → Open Settings (JSON)
Add this line:

    "remote.SSH.localServerDownload": "always"


STEP 5: Deploy to Remote Linux Host
═══════════════════════════════════════════════════════════════════

Run the installer script:

    .\install-remote.ps1 -OfflinePackageDir "C:\vscode-package" -SshHost "user@192.168.1.100"

Or use SSH config alias:

    .\install-remote.ps1 -OfflinePackageDir "C:\vscode-package" -SshHost "myserver"

For password authentication:

    .\install-remote.ps1 -OfflinePackageDir "C:\vscode-package" -SshHost "user@server" -SshPassword "pass"


STEP 6: Connect from VS Code
═══════════════════════════════════════════════════════════════════

1. Open VS Code
2. Press F1 → "Remote-SSH: Connect to Host"
3. Enter your host (user@hostname)
4. VS Code connects without downloading anything!


TROUBLESHOOTING
═══════════════════════════════════════════════════════════════════

Issue: SSH not found
Solution: Install OpenSSH Client
    Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0

Issue: Architecture detection fails
Solution: Specify manually
    .\install-remote.ps1 ... -Arch "x64"    # or "arm64"

Issue: Connection hangs
Solution: Check settings
    • Verify "remote.SSH.localServerDownload": "always" is set
    • Check commit hash matches: code --version


SECURITY RECOMMENDATIONS
═══════════════════════════════════════════════════════════════════

✓ Use SSH key-based authentication (not passwords)
✓ Verify SSH host keys before connecting
✓ Keep packages on secure storage during transfer
✓ Use User-scope installer (default, no admin needed)


For detailed documentation, see:
  • README.md
  • howto-install-vscode-airgap.md

"@

Write-Host "`nPress any key to continue..." -ForegroundColor Cyan
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

# Interactive mode - ask user what they want to do
Write-Host "`n`n========================================" -ForegroundColor Cyan
Write-Host "What would you like to do?" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "1. Download VS Code package (requires internet)" -ForegroundColor White
Write-Host "2. Install VS Code Server on remote host (offline)" -ForegroundColor White
Write-Host "3. Show detailed help" -ForegroundColor White
Write-Host "4. Exit" -ForegroundColor White
Write-Host ""

$choice = Read-Host "Enter your choice (1-4)"

switch ($choice) {
    "1" {
        Write-Host "`nStarting download script..." -ForegroundColor Green
        Write-Host ""
        
        $output = Read-Host "Output directory (press Enter for default: .\vscode-package)"
        if ([string]::IsNullOrWhiteSpace($output)) {
            $output = ".\vscode-package"
        }
        
        $version = Read-Host "VS Code version (press Enter for latest)"
        
        if ([string]::IsNullOrWhiteSpace($version)) {
            & "$PSScriptRoot\download-latest-vscode-package.ps1" -Output $output
        }
        else {
            & "$PSScriptRoot\download-latest-vscode-package.ps1" -Output $output -Version $version
        }
    }
    
    "2" {
        Write-Host "`nStarting remote installation..." -ForegroundColor Green
        Write-Host ""
        
        $packageDir = Read-Host "Package directory path"
        if ([string]::IsNullOrWhiteSpace($packageDir)) {
            Write-Host "ERROR: Package directory is required" -ForegroundColor Red
            exit 1
        }
        
        $sshHost = Read-Host "SSH host (user@hostname or alias)"
        if ([string]::IsNullOrWhiteSpace($sshHost)) {
            Write-Host "ERROR: SSH host is required" -ForegroundColor Red
            exit 1
        }
        
        $arch = Read-Host "Architecture (x64/arm64/auto, press Enter for auto)"
        if ([string]::IsNullOrWhiteSpace($arch)) {
            $arch = "auto"
        }
        
        Write-Host ""
        Write-Host "Installing to $sshHost..." -ForegroundColor Cyan
        & "$PSScriptRoot\install-remote.ps1" -OfflinePackageDir $packageDir -SshHost $sshHost -Arch $arch
    }
    
    "3" {
        Write-Host "`nOpening detailed help..." -ForegroundColor Green
        Get-Help "$PSScriptRoot\download-latest-vscode-package.ps1" -Full
        Write-Host "`n----------------------------------------`n" -ForegroundColor Cyan
        Get-Help "$PSScriptRoot\install-remote.ps1" -Full
    }
    
    "4" {
        Write-Host "`nExiting..." -ForegroundColor Yellow
        exit 0
    }
    
    default {
        Write-Host "`nInvalid choice. Please run the script again." -ForegroundColor Red
        exit 1
    }
}
