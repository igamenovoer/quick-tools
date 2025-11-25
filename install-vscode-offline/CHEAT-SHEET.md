# VS Code Offline Installation - Quick Reference Cheat Sheet

## 📥 Download (Internet-Connected Machine)

```powershell
# Latest version to default location (./vscode-package)
.\download-latest-vscode-package.ps1

# Latest version to custom location
.\download-latest-vscode-package.ps1 -Output "E:\usb\vscode"

# Specific version
.\download-latest-vscode-package.ps1 -Version "1.105.1"

# Specific version to custom location
.\download-latest-vscode-package.ps1 -o "E:\usb\vscode" -Version "1.105.1"
```

---

## 💻 Install VS Code Locally (Offline Windows Machine)

```powershell
# Run installer
.\VSCodeUserSetup-x64-1.105.1.exe

# Install extensions after VS Code is installed
code --install-extension .\ms-vscode-remote.remote-ssh-*.vsix
code --install-extension .\ms-vscode-remote.remote-ssh-edit-*.vsix

# Add to VS Code settings.json (Ctrl+Shift+P → "Preferences: Open Settings (JSON)")
"remote.SSH.localServerDownload": "always"
```

---

## 🚀 Deploy to Remote Linux Host

```powershell
# Basic - auto-detect architecture
.\install-remote.ps1 -OfflinePackageDir ".\vscode-package" -SshHost "user@server"

# Using SSH config alias
.\install-remote.ps1 -OfflinePackageDir ".\vscode-package" -SshHost "myserver"

# Manual architecture
.\install-remote.ps1 -OfflinePackageDir ".\pkg" -SshHost "user@server" -Arch "x64"

# With password (not recommended)
.\install-remote.ps1 -OfflinePackageDir ".\pkg" -SshHost "user@server" -SshPw "pass"

# Custom SSH port
.\install-remote.ps1 -OfflinePackageDir ".\pkg" -SshHost "user@server" -SshPort 2222

# Skip host key check (development only)
.\install-remote.ps1 -OfflinePackageDir ".\pkg" -SshHost "user@server" -SkipHostKeyCheck
```

---

## 🔍 Version Checking

```powershell
# Check local VS Code
.\version-check.ps1 -CheckLocal

# Check remote VS Code Server
.\version-check.ps1 -CheckRemote -SshHost "user@server"

# Check both (compatibility)
.\version-check.ps1 -CheckLocal -CheckRemote -SshHost "user@server"
```

---

## 🎯 Quick Start

```powershell
# Interactive guide and menu
.\quick-start.ps1
```

---

## 🔑 SSH Key Setup (Recommended)

```powershell
# Generate SSH key (if you don't have one)
ssh-keygen -t ed25519 -C "your_email@example.com"

# Copy key to remote (do this on internet-connected machine first)
Get-Content $env:USERPROFILE\.ssh\id_ed25519.pub | ssh user@remote "cat >> ~/.ssh/authorized_keys"

# Or manually copy the public key
type $env:USERPROFILE\.ssh\id_ed25519.pub
# Then SSH to remote and paste into ~/.ssh/authorized_keys
```

---

## 🔧 Troubleshooting Commands

```powershell
# Check if SSH is installed
Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH.Client*'

# Install OpenSSH Client
Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0

# Test SSH connection
ssh user@server

# Check VS Code installation
code --version

# Check remote architecture
ssh user@server "uname -m"

# Check remote disk space
ssh user@server "df -h ~"

# List remote VS Code Servers
ssh user@server "ls -la ~/.vscode-server/cli/servers/"

# Remove old/broken server installation
ssh user@server "rm -rf ~/.vscode-server"
```

---

## 📋 VS Code Remote-SSH Connection

```
1. Open VS Code
2. Press F1 (or Ctrl+Shift+P)
3. Type: "Remote-SSH: Connect to Host"
4. Enter: user@hostname
5. Select platform: Linux
6. Connection established!
```

---

## 📂 Important Files & Directories

### Local (Windows)
```
%USERPROFILE%\.ssh\
  ├── id_ed25519        (private key)
  ├── id_ed25519.pub    (public key)
  ├── config            (SSH config)
  └── known_hosts       (verified hosts)

%APPDATA%\Code\User\
  └── settings.json     (VS Code settings)
```

### Remote (Linux)
```
~/.vscode-server/
  └── cli/servers/
      └── Stable-<commit>/
          └── server/
              └── bin/
                  └── code-server
```

---

## 🎨 VS Code Settings Template

```json
{
  // Required for offline installation
  "remote.SSH.localServerDownload": "always",
  
  // Optional but recommended
  "remote.SSH.showLoginTerminal": true,
  "remote.SSH.connectTimeout": 60,
  
  // Disable auto-updates if fully offline
  "update.mode": "manual",
  "extensions.autoCheckUpdates": false,
  "extensions.autoUpdate": false
}
```

---

## 🐧 Remote Linux Manual Installation

If scripts fail, manual installation on Linux:

```bash
COMMIT="<your-40-char-commit-hash>"
ARCH="x64"  # or "arm64"

# Create directory
mkdir -p ~/.vscode-server/cli/servers/Stable-$COMMIT/server

# Extract (tarball should be in current directory)
tar -xzf vscode-server-linux-${ARCH}-${COMMIT}.tar.gz \
    --strip-components=1 \
    -C ~/.vscode-server/cli/servers/Stable-$COMMIT/server

# Verify
ls -la ~/.vscode-server/cli/servers/Stable-$COMMIT/server/bin/code-server

# Old layout compatibility (optional)
mkdir -p ~/.vscode-server/bin
ln -sf ~/.vscode-server/cli/servers/Stable-$COMMIT/server \
       ~/.vscode-server/bin/$COMMIT
```

---

## 📦 Package Contents

```
vscode-package/
├── VSCodeUserSetup-x64-<version>.exe           (~95 MB)
├── ms-vscode-remote.remote-ssh-*.vsix          (~1 MB)
├── ms-vscode-remote.remote-ssh-edit-*.vsix     (~0.5 MB)
├── vscode-server-linux-x64-<commit>.tar.gz     (~60 MB)
├── vscode-server-linux-arm64-<commit>.tar.gz   (~55 MB)
├── package-info.json                           (metadata)
└── README.txt                                  (instructions)

Total: ~210-220 MB
```

---

## 🔗 Useful URLs

### VS Code Downloads
```
Latest Windows: https://code.visualstudio.com/download
Latest x64 Server: https://update.code.visualstudio.com/latest/server-linux-x64/stable
Latest ARM64 Server: https://update.code.visualstudio.com/latest/server-linux-arm64/stable

Specific commit:
https://update.code.visualstudio.com/commit:<COMMIT>/server-linux-x64/stable
https://update.code.visualstudio.com/commit:<COMMIT>/server-linux-arm64/stable
```

### Extensions
```
Remote-SSH: https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-ssh
Download link: https://marketplace.visualstudio.com/_apis/public/gallery/publishers/ms-vscode-remote/vsextensions/remote-ssh/latest/vspackage
```

---

## 💡 Pro Tips

1. **Use SSH Config**: Create `~\.ssh\config` on Windows:
   ```
   Host myserver
       HostName 192.168.1.100
       User username
       Port 22
       IdentityFile ~/.ssh/id_ed25519
   ```

2. **Batch Installation**: Create a text file with multiple hosts:
   ```powershell
   $hosts = @("user@server1", "user@server2", "user@server3")
   foreach ($host in $hosts) {
       .\install-remote.ps1 -OfflinePackageDir ".\pkg" -SshHost $host
   }
   ```

3. **Version Pinning**: Always download matching versions:
   - Check local: `code --version`
   - Download that exact version
   - Deploy to all remotes

4. **Security**: Use SSH keys, not passwords:
   ```powershell
   ssh-keygen -t ed25519
   ssh-copy-id user@server
   ```

---

## ⚠️ Common Pitfalls

❌ **Mismatch commit hashes** → Connection hangs
✅ Ensure local and remote commits match

❌ **Wrong architecture** → Server won't start
✅ Check with `uname -m` on Linux (x86_64 = x64, aarch64 = arm64)

❌ **Forgot settings.json** → Attempts download
✅ Add `"remote.SSH.localServerDownload": "always"`

❌ **Password in command** → Security risk
✅ Use SSH keys or omit password (prompt interactively)

❌ **Old VS Code version** → Path mismatch
✅ Use VS Code >= 1.82 for new server path layout

---

## 📞 Get Help

```powershell
# View script help
Get-Help .\download-latest-vscode-package.ps1 -Full
Get-Help .\install-remote.ps1 -Full
Get-Help .\version-check.ps1 -Full

# View README
code README.md

# Interactive guide
.\quick-start.ps1
```

---

**Happy Coding in Air-Gapped Environments! 🚀**
