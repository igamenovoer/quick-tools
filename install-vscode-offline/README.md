# VS Code Offline Installation Scripts for Air-Gapped Systems

This directory contains PowerShell scripts to automate VS Code installation in air-gapped environments, following the guide in `howto-install-vscode-airgap.md`.

## Overview

Two scripts work together to enable completely offline VS Code Remote-SSH development:

1. **`download-latest-vscode-package.ps1`** - Run on an internet-connected machine to download all required components
2. **`install-remote.ps1`** - Run on the offline Windows machine to deploy VS Code Server to remote Linux hosts

## Prerequisites

### On Internet-Connected Machine (for downloading)
- Windows 10 or later
- PowerShell 5.1 or later
- Internet connection

### On Offline Windows Machine (for installation)
- Windows 10 or later
- PowerShell 5.1 or later
- OpenSSH Client installed (built into Windows 10/11, or install via `Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0`)
- Network connectivity to target Linux hosts

### On Target Linux Hosts
- SSH server running
- User account with home directory access
- tar utility (standard on all Linux distributions)

## Script 1: Download Components

### Basic Usage

Download the latest VS Code and all required components:

```powershell
.\download-latest-vscode-package.ps1
```

This creates a `vscode-package` directory in the current location with all necessary files.

### Advanced Usage

Specify output directory and version:

```powershell
# Download to specific directory
.\download-latest-vscode-package.ps1 -Output "C:\Temp\vscode-offline"

# Download specific version
.\download-latest-vscode-package.ps1 -Version "1.105.1"

# Combine both
.\download-latest-vscode-package.ps1 -Output "D:\VSCode" -Version "1.105.1"

# Use short parameter names
.\download-latest-vscode-package.ps1 -o ".\my-package"
```

### What Gets Downloaded

The script downloads:

1. **VS Code Windows Installer** (x64, User version)
2. **Remote-SSH Extension** (.vsix)
3. **Remote-SSH: Editing Configuration Files Extension** (.vsix)
4. **VS Code Server for Linux x64** (.tar.gz)
5. **VS Code Server for Linux ARM64** (.tar.gz)

Plus:
- `package-info.json` - Metadata about downloaded components
- `README.txt` - Installation instructions

### Output Structure

```
vscode-package/
├── VSCodeUserSetup-x64-1.105.1.exe
├── ms-vscode-remote.remote-ssh-latest.vsix
├── ms-vscode-remote.remote-ssh-edit-latest.vsix
├── vscode-server-linux-x64-<commit-hash>.tar.gz
├── vscode-server-linux-arm64-<commit-hash>.tar.gz
├── package-info.json
└── README.txt
```

## Script 2: Install on Remote Linux Host

### Basic Usage

Install VS Code Server to a remote Linux host:

```powershell
.\install-remote.ps1 -OfflinePackageDir ".\vscode-package" -SshHost "user@192.168.1.100"
```

### Advanced Usage

```powershell
# Use SSH config alias
.\install-remote.ps1 -OfflinePackageDir "C:\vscode-offline" -SshHost "myserver"

# Specify architecture manually (if auto-detection fails)
.\install-remote.ps1 -OfflinePackageDir ".\vscode-package" -SshHost "user@server" -Arch "x64"

# Use custom SSH port
.\install-remote.ps1 -OfflinePackageDir ".\vscode-package" -SshHost "user@server" -SshPort 2222

# Skip host key verification (not recommended for production)
.\install-remote.ps1 -OfflinePackageDir ".\vscode-package" -SshHost "user@server" -SkipHostKeyCheck

# Password authentication (you'll be prompted, or use -SshPassword parameter)
# Note: Key-based authentication is more secure and recommended
.\install-remote.ps1 -OfflinePackageDir ".\vscode-package" -SshHost "user@server" -SshPassword "mypassword"

# Or use short parameter names
.\install-remote.ps1 -OfflinePackageDir ".\pkg" -SshHost "user@server" -SshPw "pass"
```

### What the Script Does

1. Validates the offline package directory
2. Detects remote Linux architecture (x64 or ARM64)
3. Selects the appropriate VS Code Server tarball
4. Copies the tarball to the remote host via SCP
5. Extracts the server to `~/.vscode-server/cli/servers/Stable-<commit>/server/`
6. Creates backward-compatibility symlink
7. Verifies installation
8. Cleans up temporary files

### Supported Architectures

- **x64** (x86_64, amd64) - Most Intel/AMD Linux servers
- **arm64** (aarch64) - ARM-based systems like Raspberry Pi 4, AWS Graviton

The script auto-detects architecture by default. Use `-Arch` parameter to override.

## Complete Workflow Example

### Step 1: On Internet-Connected Machine C

```powershell
# Download latest version
.\download-latest-vscode-package.ps1 -Output "E:\usb-drive\vscode-offline"

# Or download specific version
.\download-latest-vscode-package.ps1 -Output "E:\usb-drive\vscode-offline" -Version "1.105.1"
```

### Step 2: Transfer to Offline Windows Machine A

Copy the entire `vscode-offline` directory from the USB drive to the offline Windows machine.

### Step 3: On Offline Windows Machine A

#### Install VS Code Locally

```powershell
cd C:\vscode-offline

# Install VS Code
.\VSCodeUserSetup-x64-1.105.1.exe

# Install Remote-SSH extension
code --install-extension .\ms-vscode-remote.remote-ssh-latest.vsix
code --install-extension .\ms-vscode-remote.remote-ssh-edit-latest.vsix
```

#### Configure VS Code Settings

Open VS Code Settings (JSON) and add:

```json
{
  "remote.SSH.localServerDownload": "always"
}
```

#### Deploy to Remote Linux Host B

```powershell
# Deploy to Linux server
.\install-remote.ps1 -OfflinePackageDir "C:\vscode-offline" -SshHost "user@192.168.1.50"

# Or if using SSH config
.\install-remote.ps1 -OfflinePackageDir "C:\vscode-offline" -SshHost "mylinuxserver"
```

### Step 4: Connect from VS Code

1. Open VS Code on machine A
2. Click Remote Explorer icon (or press F1 → "Remote-SSH: Connect to Host")
3. Select your target host
4. VS Code connects without downloading anything!

## SSH Authentication

### Recommended: Key-Based Authentication

For better security and automation, use SSH key-based authentication:

```powershell
# Generate SSH key (if you don't have one)
ssh-keygen -t ed25519 -C "your_email@example.com"

# Copy public key to remote host (do this on the internet-connected machine)
# Method 1: Using ssh-copy-id (if available on Windows)
ssh-copy-id user@remote-host

# Method 2: Manually
Get-Content $env:USERPROFILE\.ssh\id_ed25519.pub | ssh user@remote-host "cat >> ~/.ssh/authorized_keys"

# Method 3: Copy the key file and manually append on remote
type $env:USERPROFILE\.ssh\id_ed25519.pub
# Then SSH to remote and paste into ~/.ssh/authorized_keys
```

### Password Authentication

If you must use password authentication:

```powershell
# You'll be prompted for password interactively
.\install-remote.ps1 -OfflinePackageDir ".\vscode-package" -SshHost "user@server"

# Or provide password in command (NOT RECOMMENDED - visible in history)
.\install-remote.ps1 -OfflinePackageDir ".\vscode-package" -SshHost "user@server" -SshPassword "yourpassword"
```

**Security Note:** Password authentication is less secure. Use key-based authentication in production environments.

## Troubleshooting

### Issue: "SSH command not found"

**Solution:** Install OpenSSH Client:

```powershell
# Check if installed
Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH.Client*'

# Install if not present
Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0
```

### Issue: "Could not fetch latest version info"

**Solution:** Either:
1. Check internet connection on the download machine
2. Specify version explicitly: `-Version "1.105.1"`
3. The script will try to continue with available information

### Issue: "Could not detect architecture"

**Solution:**
1. Manually specify architecture: `-Arch "x64"` or `-Arch "arm64"`
2. Check SSH connectivity to the remote host
3. Verify the remote host is running Linux

### Issue: "VS Code Server directory not found" after installation

**Causes:**
- Wrong architecture selected
- Extraction failed
- Insufficient disk space on remote host

**Solutions:**
1. Check remote disk space: `ssh user@host "df -h"`
2. Manually verify: `ssh user@host "ls -la ~/.vscode-server/cli/servers/"`
3. Re-run with correct architecture: `-Arch "x64"` or `-Arch "arm64"`

### Issue: "Connection hangs when trying to connect from VS Code"

**Solutions:**
1. Verify the commit hash matches:
   - On Windows: `code --version`
   - On Linux: Check directory name in `~/.vscode-server/cli/servers/`
2. Ensure `"remote.SSH.localServerDownload": "always"` is set in VS Code settings
3. Check server installation: `ssh user@host "ls -la ~/.vscode-server/cli/servers/Stable-*/server/bin/code-server"`

### Issue: Password authentication not working

**Solutions:**
1. Use interactive password prompt (omit `-SshPassword` parameter)
2. Set up SSH key-based authentication instead
3. Verify password is correct
4. Check if remote host allows password authentication (`/etc/ssh/sshd_config`)

### Issue: "Permission denied" when extracting on remote

**Solutions:**
1. Ensure you have write access to your home directory
2. Check disk space: `df -h $HOME`
3. Verify tar is installed: `which tar`

## Version Compatibility

The scripts are tested with:
- **VS Code:** 1.95.0 - 1.105.1 (October 2025)
- **Windows:** 10 (1809+), 11
- **PowerShell:** 5.1, 7.0+
- **Linux:** Any distribution with tar and SSH server

## Security Best Practices

1. ✅ **Use SSH key-based authentication** instead of passwords
2. ✅ **Verify host keys** (avoid `-SkipHostKeyCheck` in production)
3. ✅ **Keep packages on secure storage** during transfer
4. ✅ **Verify downloads** before copying to offline systems
5. ✅ **Use User-scope VS Code installer** (default, doesn't require admin)
6. ✅ **Update regularly** by downloading new packages periodically

## File Sizes (Approximate)

- VS Code Windows Installer: ~95 MB
- Remote-SSH Extension: ~1 MB
- Remote-SSH Edit Extension: ~0.5 MB
- VS Code Server (x64): ~60 MB
- VS Code Server (ARM64): ~55 MB

**Total package size:** ~210-220 MB

## Additional Resources

- **Detailed Guide:** See `howto-install-vscode-airgap.md` in this directory
- **VS Code Docs:** https://code.visualstudio.com/docs/remote/ssh
- **OpenSSH for Windows:** https://learn.microsoft.com/en-us/windows-server/administration/openssh/

## License

These scripts are provided as-is for use with VS Code offline installations. VS Code and its extensions are subject to their respective licenses.

## Support

For issues with:
- **These scripts:** Check troubleshooting section above
- **VS Code itself:** https://github.com/microsoft/vscode/issues
- **Remote-SSH extension:** https://github.com/microsoft/vscode-remote-release/issues
