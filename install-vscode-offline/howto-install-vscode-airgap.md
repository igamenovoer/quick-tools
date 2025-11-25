# How to Install VS Code in Air-Gapped Environment (Two-Container Setup)

This guide describes how to set up **VS Code Remote-SSH development in a completely air-gapped environment** using two containers:

- **Terminal Container (A)**: Runs VS Code GUI with X11/WSLg support
- **Remote Container (B)**: SSH server for remote development (simulates GPU server)

After downloading required packages once, **no internet connection is needed** for setup or operation.

---

## What We'll Do (Overview)

1. On an internet-connected computer (**C**), download all required packages to USB/storage
2. Transfer packages to air-gapped environment
3. Build **Terminal Container (A)** with VS Code GUI from offline packages
4. Build **Remote Container (B)** with SSH server from offline packages
5. Install VS Code Server on **B** using pre-downloaded tarballs and cache detection
6. Connect from **A** → **B** via Remote-SSH (completely offline)

---

## 0. Prerequisites

### On the Air-Gapped Host

- **Windows 10/11** with WSLg (for X11 GUI support), or **Linux** with X11
- **Podman** or **Docker** installed and working
- **Repository cloned** at a path like: `C:\Users\<username>\systalk\install-vscode-offline`

### Directory Structure

```
install-vscode-offline/
├── simulate/
│   ├── pkgs/                          # All .deb packages and tarballs go here
│   ├── terminal.Dockerfile            # Terminal container image
│   ├── server.Dockerfile              # Remote server container image
│   ├── deprecated/                    # Legacy scripts (moved here)
│   │   └── podman-compose-both.yaml   # Old orchestration file
│   ├── helper-scripts/                # Installation scripts
│   ├── checks/                        # Test and verification scripts
│   ├── guides/                        # Documentation guides
│   └── vscode/                        # VS Code config files
├── download-latest-vscode-package.ps1 # Package downloader (run on C)
└── install-remote.ps1                 # VS Code Server installer
```

---

## 1. On Connected Machine (C) → Build Offline Package Kit

Goal: Download **everything** needed for a fully offline installation.

### Step 1.1: Get Your Target VS Code Version

On the air-gapped host (or a similar system), check what VS Code version you want:

```powershell
# If VS Code is already installed
code --version

# Output:
# 1.106.2
# 1e3c50d64110be466c0b4a45222e81d2c9352888  ← This is the COMMIT hash
# x64
```

**Save this COMMIT hash** - you'll need it to download matching server components.

### Step 1.2: Download VS Code Components

On machine **C** (with internet), run:

```powershell
cd C:\path\to\install-vscode-offline

# Download VS Code, extensions, and server components
.\download-latest-vscode-package.ps1 -Output ".\vscode-package"
```

This downloads:
- VS Code installer for Windows (if needed)
- VS Code tarball for Linux (`vscode-linux-x64-*.tar.gz`)
- Remote-SSH extension (`.vsix` files)
- VS Code Server tarball (`vscode-server-linux-x64-<COMMIT>.tar.gz`)

### Step 1.3: Download VS Code CLI Component

The Remote-SSH extension also needs the CLI component. Download it manually:

```powershell
$COMMIT = "1e3c50d64110be466c0b4a45222e81d2c9352888"  # Use your commit hash

cd .\vscode-package

# Download CLI for Alpine/Linux (10MB)
curl -fL "https://update.code.visualstudio.com/commit:${COMMIT}/cli-alpine-x64/stable" `
  -o "vscode-cli-alpine-x64-${COMMIT}.tar.gz"
```

### Step 1.4: Download Ubuntu System Packages (.deb files)

On an **Ubuntu 24.04** system with internet (or using a tool like `apt-offline`), download all required `.deb` packages:

**For Terminal Container:**
```bash
# Required packages for VS Code GUI + X11 + SSH client
apt-get download \
  wget curl tar ca-certificates \
  libgtk-3-0 libxss1 libasound2 libgbm1 \
  openssh-client sudo bash git \
  libx11-xcb1 libxkbfile1 libsecret-1-0 \
  fonts-dejavu fonts-liberation

# Download dependencies
apt-cache depends <package-name> --recurse --no-recommends \
  | grep "^\w" | xargs apt-get download
```

**For Server Container:**
```bash
# Required packages for SSH server
apt-get download \
  openssh-server sudo tar curl ca-certificates bash
```

**Copy all `.deb` files** to `install-vscode-offline/simulate/pkgs/`

### Step 1.5: Organize the Offline Kit

Your offline package directory should now contain:

```
install-vscode-offline/
├── vscode-package/
│   ├── vscode-linux-x64.tar.gz                                    # VS Code GUI (~100MB)
│   ├── vscode-server-linux-x64-<COMMIT>.tar.gz                    # VS Code Server (~70MB)
│   ├── vscode-cli-alpine-x64-<COMMIT>.tar.gz                      # VS Code CLI (~10MB)
│   ├── ms-vscode-remote.remote-ssh-latest.vsix                    # Remote-SSH extension
│   ├── ms-python.python-latest.vsix                               # Python extension (optional)
│   └── eamodio.gitlens-latest.vsix                                # GitLens (optional)
└── simulate/
    └── pkgs/
        ├── *.deb                                                   # All Ubuntu packages
        ├── vscode-linux-x64.tar.gz                                # (copy from vscode-package)
        ├── vscode-server-linux-x64-<COMMIT>.tar.gz                # (copy from vscode-package)
        ├── vscode-cli-alpine-x64-<COMMIT>.tar.gz                  # (copy from vscode-package)
        └── *.vsix                                                  # (copy extension files)
```

**Transfer this entire directory** to the air-gapped environment via USB or other offline media.

---

## 2. Build Terminal Container (A) - Offline

Goal: Create a container that runs VS Code GUI with X11 support, using only offline packages.

### Step 2.1: Review Terminal Dockerfile

The `simulate/terminal.Dockerfile` is configured to:
- Install from local `.deb` cache in `pkgs/`
- Extract VS Code from local tarball
- Install extensions from local `.vsix` files
- Configure X11 display and SSH client

**No modifications needed** if your `pkgs/` directory is complete.

### Step 2.2: Build Terminal Image

```powershell
cd C:\Users\<username>\systalk\install-vscode-offline\simulate

# Build terminal image (no internet required if pkgs/ is complete)
podman build -f terminal.Dockerfile -t localhost/vscode-airgap-terminal:latest .
```

This process:
- ✅ Installs all system packages from `pkgs/*.deb`
- ✅ Extracts VS Code from `pkgs/vscode-linux-x64.tar.gz`
- ✅ Creates user `dev` with home directory
- ✅ Configures X11 and SSH

**Verification**: Build should complete without any network access. If it fails, you're missing `.deb` files in `pkgs/`.

---

## 3. Build Remote Server Container (B) - Offline

Goal: Create an SSH server container that will host the VS Code Server, using only offline packages.

### Step 3.1: Build Server Image

```powershell
cd C:\Users\<username>\systalk\install-vscode-offline\simulate

# Build server image (no internet required)
podman build -f server.Dockerfile -t localhost/vscode-airgap-server:latest .
```

This creates:
- ✅ Ubuntu 24.04 with SSH server
- ✅ User `vscode-tester` (password: `123456`)
- ✅ All system packages from `pkgs/*.deb`
- ✅ Pre-configured SSH with key authentication

---

## 4. Install VS Code Server on Remote Container (B) - Offline

Goal: Pre-install VS Code Server on container **B** so Remote-SSH connections work without downloads.

### Step 4.1: Understanding the Cache Detection Mechanism

**Key Discovery**: VS Code Remote-SSH looks for specific files before attempting downloads. If these files exist with correct naming, VS Code **skips downloading entirely**.

Required files in `~/.vscode-server/` on the remote:

1. **`vscode-cli-${COMMIT}.tar.gz`** - The CLI tarball
2. **`vscode-cli-${COMMIT}.tar.gz.done`** - A marker file (copy of CLI tarball)
3. **`vscode-server.tar.gz`** - The server tarball (generic name, not commit-specific)
4. **`cli/servers/Stable-${COMMIT}/server/`** - Extracted server (optional but recommended)

### Step 4.2: Start Containers with Podman Compose

```powershell
cd C:\Users\<username>\systalk\install-vscode-offline\simulate

# Start both containers on internal network
# Note: podman-compose-both.yaml has been moved to deprecated/
podman-compose -f simulate/deprecated/podman-compose-both.yaml up -d
```

This creates:
- **vscode-terminal** - Terminal container with VS Code GUI
- **vscode-remote** - Server container with SSH
- **simulate_vscode-airgap-both** - Internal network (no internet access)

### Step 4.3: Install VS Code Server Using Helper Script

We provide a helper script that automates the installation:

```powershell
cd C:\Users\<username>\systalk\install-vscode-offline

# Method 1: Using install-remote.ps1 (requires temporary SSH port exposure)
# Temporarily expose SSH port (for installation only)
podman port add vscode-remote 4444:22

# Run installer
.\install-remote.ps1 `
    -OfflinePackageDir ".\vscode-package" `
    -SshHost "vscode-tester@localhost" `
    -SshPort 4444 `
    -SshPassword "123456"

# Remove port exposure after installation
podman port remove vscode-remote 4444:22
```

**Or Method 2: Manual installation inside the container:**

```powershell
# Copy the helper script
podman cp simulate/helper-scripts/install-vscode-server-on-remote.sh vscode-remote:/tmp/

# Execute as vscode-tester user
podman exec -u vscode-tester -it vscode-remote bash /tmp/install-vscode-server-on-remote.sh
```

### Step 4.4: Pre-Place Cache Files for Offline Detection

This is the **critical step** for true offline operation. Place the cache files that VS Code looks for:

```powershell
# Copy VS Code Server tarball to the expected location
podman cp simulate/pkgs/vscode-server-linux-x64-<COMMIT>.tar.gz `
    vscode-remote:/home/vscode-tester/.vscode-server/vscode-server.tar.gz

# Copy VS Code CLI tarball
podman cp simulate/pkgs/vscode-cli-alpine-x64-<COMMIT>.tar.gz `
    vscode-remote:/home/vscode-tester/.vscode-server/vscode-cli-<COMMIT>.tar.gz

# Create the .done marker file
podman exec vscode-remote bash -c `
    "cp /home/vscode-tester/.vscode-server/vscode-cli-<COMMIT>.tar.gz \
        /home/vscode-tester/.vscode-server/vscode-cli-<COMMIT>.tar.gz.done"

# Fix permissions
podman exec vscode-remote chown -R vscode-tester:vscode-tester \
    /home/vscode-tester/.vscode-server/
```

### Step 4.5: Verify Installation

Check that all required files are in place:

```powershell
podman exec vscode-remote ls -lh /home/vscode-tester/.vscode-server/

# Expected output:
# drwxr-xr-x cli/
# drwxr-xr-x data/
# drwxr-xr-x extensions/
# -rw-rw-rw- vscode-cli-<COMMIT>.tar.gz           (10MB)
# -rw-r--r-- vscode-cli-<COMMIT>.tar.gz.done      (10MB)
# -rw-rw-rw- vscode-server.tar.gz                 (70MB)
```

And verify the extracted server:

```powershell
podman exec vscode-remote ls /home/vscode-tester/.vscode-server/cli/servers/Stable-<COMMIT>/server/bin/

# Expected output:
# code-server  ← This is the VS Code Server binary
```

---

## 5. Install VS Code in Terminal Container (A) - Offline

Goal: Install VS Code GUI and extensions in the terminal container using only offline packages.

### Step 5.1: Install VS Code Using Helper Script

```powershell
cd C:\Users\<username>\systalk\install-vscode-offline

# Run the post-build installation script (moved to deprecated/)
.\simulate\deprecated\install-vscode-in-container.ps1
```

This script:
- ✅ Installs VS Code from `pkgs/vscode-linux-x64.tar.gz`
- ✅ Creates `/usr/local/bin/code` symlink
- ✅ Installs all `.vsix` extensions from `pkgs/`
- ✅ Sets up proper ownership for `dev` user

### Step 5.2: Configure VS Code Settings (Optional)

Pre-configure VS Code settings for air-gapped operation:

```powershell
# The settings file already exists at simulate/vscode/settings.json
# It contains:
# {
#     "remote.SSH.localServerDownload": "off",
#     "remote.SSH.useExecServer": false,
#     "remote.SSH.showLoginTerminal": true,
#     "update.mode": "manual",
#     "extensions.autoCheckUpdates": false,
#     "extensions.autoUpdate": false
# }

# Copy to container (already done during build)
podman cp simulate/vscode/settings.json vscode-terminal:/home/dev/.config/Code/User/
podman exec vscode-terminal chown dev:dev /home/dev/.config/Code/User/settings.json
```

### Step 5.3: Verify Installation

```powershell
# Check VS Code version
podman exec vscode-terminal code --version

# List installed extensions
podman exec vscode-terminal code --list-extensions

# Expected output:
# eamodio.gitlens
# ms-python.python
# ms-vscode-remote.remote-ssh
```

---

## 6. Launch VS Code GUI (from Terminal Container A)

Goal: Display VS Code GUI on the host using X11/WSLg.

### Step 6.1: Launch Using Helper Script

```powershell
cd C:\Users\<username>\systalk\install-vscode-offline

# Launch VS Code with proper flags for Chromium/Electron (moved to deprecated/)
.\simulate\deprecated\launch-vscode-in-terminal-container.ps1
```

This launches VS Code with required flags:
- `--disable-gpu` - Avoids GPU issues with X11 forwarding
- `--no-sandbox` - Disables Chromium sandbox (safe in containers)
- `--disable-dev-shm-usage` - Uses `/tmp` instead of `/dev/shm`

**Why these flags?** See `issues/issue-podman-vscode-gui.md` for technical details.

### Step 6.2: Manual Launch (Alternative)

```powershell
# Direct execution
podman exec -it vscode-terminal bash -c \
    "code --disable-gpu --no-sandbox --disable-dev-shm-usage"
```

The VS Code window should appear on your host desktop via WSLg/X11.

---

## 7. Connect from Terminal (A) to Remote Server (B) via Remote-SSH - Fully Offline

Goal: Establish Remote-SSH connection **without any internet access**.

### Step 7.1: Configure SSH Connection

In VS Code (running in terminal container):

1. Press **F1** → Type: `Remote-SSH: Connect to Host...`
2. Enter: `vscode-tester@vscode-remote`
3. Select platform: **Linux**
4. Password: `123456` (or use pre-configured SSH key)

**Alternative**: Use SSH config file (already configured in terminal container):

```bash
# Inside terminal container, check SSH config
cat ~/.ssh/config

# Output:
# Host vscode-remote
#     HostName vscode-remote
#     User vscode-tester
#     IdentityFile ~/.ssh/vscode_ssh_key
```

Just select **vscode-remote** from the Remote Explorer in VS Code.

### Step 7.2: What Happens During Connection

When you connect, VS Code Remote-SSH will:

1. ✅ Check local settings: `localServerDownload` is `off`
2. ✅ SSH to `vscode-remote` container
3. ✅ Look for VS Code Server on remote at:
   - `~/.vscode-server/vscode-cli-<COMMIT>.tar.gz.done` ← Found!
   - `~/.vscode-server/vscode-server.tar.gz` ← Found!
   - `~/.vscode-server/cli/servers/Stable-<COMMIT>/server/` ← Found!
4. ✅ **Skip all downloads** - use existing installation
5. ✅ Start VS Code Server and establish connection

### Step 7.3: Verify Offline Operation

Once connected (green indicator shows `SSH: vscode-remote`):

1. Open a terminal in VS Code (it runs on container B)
2. Verify no internet:

```bash
# Inside the remote session (container B)
ping -c 3 8.8.8.8
# Should fail (no internet access)

curl https://example.com
# Should fail (no internet access)

# But VS Code works perfectly!
ls -la
code --version
# Everything works because server was pre-installed
```

3. Open a folder: `/home/vscode-tester/`
4. Create files, run code, use extensions - all offline!

---

## 8. Installing Additional Extensions (Offline)

Goal: Add more extensions to the remote environment without internet.

### Step 8.1: Download Extensions on Connected Machine (C)

On machine C with internet:

```powershell
# Download extension .vsix file from VS Code Marketplace
# Example: Python extension
# Visit: https://marketplace.visualstudio.com/items?itemName=ms-python.python
# Download the .vsix file
```

### Step 8.2: Install Extension on Remote (B)

Method 1: Via VS Code GUI (while connected to remote)

1. In VS Code: **Extensions** → **"⋯" menu** → **Install from VSIX...**
2. Choose where to install: **Install on SSH: vscode-remote**
3. VS Code will copy the `.vsix` to the remote and install (no internet needed)

Method 2: Via Command Line

```powershell
# Copy .vsix to remote container
podman cp extension.vsix vscode-remote:/tmp/

# Install as vscode-tester user
podman exec -u vscode-tester vscode-remote bash -c \
    "~/.vscode-server/cli/servers/Stable-<COMMIT>/server/bin/code-server \
     --install-extension /tmp/extension.vsix"
```

---

## 9. Stopping and Restarting the Environment

### Stop Containers

```powershell
cd C:\Users\<username>\systalk\install-vscode-offline

# Stop both containers (using deprecated compose file)
podman-compose -f simulate/deprecated/podman-compose-both.yaml down
```

### Restart Containers

```powershell
# Start both containers
podman-compose -f simulate/deprecated/podman-compose-both.yaml up -d

# Launch VS Code GUI
.\simulate\deprecated\launch-vscode-in-terminal-container.ps1

# Connect via Remote-SSH (same as before)
```

**All data persists** because we use named volumes:
- `vscode-terminal-home` - Terminal container home directory
- `vscode-remote-home` - Remote container home directory

---

## 10. Troubleshooting

### VS Code GUI Doesn't Appear

**Problem**: VS Code window doesn't show on host

**Solution**: Check Chromium/Electron flags
```powershell
# Ensure these flags are used:
code --disable-gpu --no-sandbox --disable-dev-shm-usage

# On Windows WSLg, check DISPLAY variable
echo $DISPLAY
# Should be: :0 or similar
```

See: `issues/issue-podman-vscode-gui.md`

### Remote-SSH Connection Hangs on "Downloading VS Code Server"

**Problem**: VS Code tries to download server despite pre-installation

**Cause**: Cache files are missing or incorrectly named

**Solution**: Verify exact filenames and locations
```powershell
podman exec vscode-remote ls -la /home/vscode-tester/.vscode-server/

# Must have EXACTLY these names:
# vscode-cli-<COMMIT>.tar.gz
# vscode-cli-<COMMIT>.tar.gz.done  ← Must end with .done
# vscode-server.tar.gz              ← Generic name, NOT commit-specific
```

See: `simulate/guides/about-coder-server-placement.md`

### Remote-SSH Shows "Failed to Download VS Code Server"

**Problem**: LocalDownloadFailed error

**Cause**: VS Code trying to download on local machine (terminal container) which also has no internet

**Solution 1**: Ensure `localServerDownload` setting is `off`
```json
{
    "remote.SSH.localServerDownload": "off"
}
```

**Solution 2**: Ensure server is properly installed on remote
```powershell
podman exec vscode-remote ls ~/.vscode-server/cli/servers/Stable-<COMMIT>/server/bin/code-server
# Should exist
```

### SSH Connection Refused

**Problem**: Cannot SSH from terminal to remote

**Cause**: Containers not on same network or SSH not running

**Solution**: Check network and SSH status
```powershell
# Check both containers are running
podman ps

# Check SSH is running on remote
podman exec vscode-remote service ssh status

# Check network connectivity
podman exec vscode-terminal ping -c 3 vscode-remote
# Should succeed (internal network)
```

### Extensions Not Working on Remote

**Problem**: Extensions show as disabled or not found

**Cause**: Extensions installed locally but not on remote

**Solution**: Install extensions on remote
```powershell
# Check where extension is installed
# In VS Code: Extensions → Right-click extension → Properties
# Look for "Extension Location"

# If showing "Local", install on remote using "Install on SSH: vscode-remote"
```

---

## 11. Quick Reference Checklist

### Before Going Offline (on machine C with internet):

- [ ] Download VS Code Linux tarball (`vscode-linux-x64.tar.gz`)
- [ ] Download VS Code Server tarball for your commit (`vscode-server-linux-x64-<COMMIT>.tar.gz`)
- [ ] Download VS Code CLI tarball for your commit (`vscode-cli-alpine-x64-<COMMIT>.tar.gz`)
- [ ] Download all required `.vsix` extension files
- [ ] Download all Ubuntu `.deb` packages to `simulate/pkgs/`
- [ ] Transfer entire `install-vscode-offline/` directory to air-gapped environment

### In Air-Gapped Environment:

- [ ] Build terminal image: `podman build -f simulate/terminal.Dockerfile ...`
- [ ] Build server image: `podman build -f simulate/server.Dockerfile ...`
- [ ] Start containers: `podman-compose -f simulate/deprecated/podman-compose-both.yaml up -d`
- [ ] Install VS Code Server on remote: Run `simulate/helper-scripts/install-vscode-server-on-remote.sh`
- [ ] Pre-place cache files on remote (CLI tarball + .done marker + server tarball)
- [ ] Install VS Code in terminal: Run `simulate/deprecated/install-vscode-in-container.ps1`
- [ ] Launch VS Code GUI: Run `simulate/deprecated/launch-vscode-in-terminal-container.ps1`
- [ ] Connect via Remote-SSH: `F1` → `Remote-SSH: Connect to Host...` → `vscode-remote`

### Verify Offline Operation:

- [ ] VS Code GUI displays on host (WSLg/X11)
- [ ] Remote-SSH connection succeeds without "Downloading..." messages
- [ ] Terminal shows `SSH: vscode-remote` indicator
- [ ] Can open folders and files on remote
- [ ] Extensions work on remote
- [ ] No internet access on either container (test with `ping` / `curl`)

---

## 12. Files and Scripts Reference

### Key Files

| File | Purpose |
|------|---------|
| `simulate/terminal.Dockerfile` | Builds terminal container with VS Code GUI |
| `simulate/server.Dockerfile` | Builds remote server container with SSH |
| `simulate/deprecated/podman-compose-both.yaml` | Orchestrates both containers (deprecated) |
| `simulate/helper-scripts/install-vscode-server-on-remote.sh` | Installs VS Code Server on remote |
| `simulate/helper-scripts/terminal-install-in-container.sh` | Installs VS Code in terminal container |
| `simulate/deprecated/install-vscode-in-container.ps1` | PowerShell wrapper for terminal installation (deprecated) |
| `simulate/deprecated/launch-vscode-in-terminal-container.ps1` | Launches VS Code GUI with proper flags (deprecated) |
| `simulate/vscode/settings.json` | VS Code settings for air-gapped operation |

### Documentation

| File | Content |
|------|---------|
| `howto-install-vscode-airgap.md` | Full installation and simulation guide (this file) |
| `howto-ssh-non-interactive-windows.md` | Detailed SSH/automation instructions for Windows |
| `simulate/guides/about-coder-server-placement.md` | **Cache file detection mechanism** (important!) |
| `issues/issue-podman-vscode-gui.md` | WSLg/X11 GUI troubleshooting |
| `simulate/helper-scripts/README-INSTALL-SCRIPT.md` | Installation script documentation |

---

## 13. Differences from Standard Installation

### Standard (Online) Installation

1. Install VS Code on Windows
2. Install Remote-SSH extension
3. Connect to remote Linux server
4. VS Code **downloads** server from internet on first connect
5. Extensions **auto-update** from Marketplace

### Our Air-Gapped Installation

1. Build terminal container with VS Code from offline tarball
2. Install Remote-SSH extension from offline `.vsix`
3. **Pre-install** VS Code Server on remote from offline tarball
4. **Pre-place cache files** so VS Code finds them and skips downloads
5. Connect to remote - **no downloads occur**
6. Extensions installed from offline `.vsix` files - **no auto-updates**

**Key Innovation**: The cache file detection mechanism (`vscode-cli-<COMMIT>.tar.gz.done` + `vscode-server.tar.gz`) is the secret to making Remote-SSH work completely offline.

---

## 14. Adapting for Physical Machines

This guide uses containers for simulation, but the same principles apply to physical machines:

### Terminal Machine (Physical Windows PC)

Instead of building a container:
1. Install VS Code from offline installer
2. Install Remote-SSH extension from `.vsix`
3. Configure settings: `"remote.SSH.localServerDownload": "off"`

### Remote Machine (Physical Linux Server)

Instead of building a container:
1. Ensure SSH server is installed and running
2. Create directory: `~/.vscode-server/`
3. Copy and place cache files exactly as described in Step 4.4
4. Extract server to: `~/.vscode-server/cli/servers/Stable-<COMMIT>/server/`

The connection process is **identical** - VS Code will use the same cache detection mechanism.

---

## References

- [VS Code Remote Development Documentation](https://code.visualstudio.com/docs/remote/ssh)
- [VS Code Offline Installation FAQ](https://code.visualstudio.com/docs/remote/faq)
- [How to install vscode-server offline (1.82.0+)](https://stackoverflow.com/questions/77068802/how-do-i-install-vscode-server-offline-on-a-server-for-vs-code-version-1-82-0-or)
- [Remote-SSH in Air-Gapped Environments](https://stackoverflow.com/questions/56718453/using-remote-ssh-in-vscode-on-a-target-machine-that-only-allows-inbound-ssh-co)
- [LocalDownloadFailed Error Fix](https://stackoverflow.com/questions/79622709/vs-code-server-localdownloadfailed-error-localdownloadfailed-failed-to-down)

---

## Conclusion

This guide provides a **complete, verified, offline-capable VS Code Remote-SSH setup** using containers. The key innovations are:

1. **Cache File Detection**: Pre-placing specific files so VS Code skips all downloads
2. **Offline Package Management**: All `.deb`, tarballs, and `.vsix` files pre-downloaded
3. **Container Orchestration**: Podman Compose for easy management
4. **GUI Support**: WSLg/X11 with proper Chromium flags

After following these steps, you have a **fully functional remote development environment** that requires **zero internet connectivity** during operation.
