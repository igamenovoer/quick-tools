# Terminal Container Post-Build Installation Guide

This guide explains how to use the `terminal-install-in-container.sh` script to install VS Code and extensions in a running terminal container.

## Overview

The `terminal-install-in-container.sh` script is designed to be executed **after** the terminal Docker container is built and running. It allows you to:

1. Install VS Code from the offline tarball (`/pkgs-host/vscode-linux-*.tar.gz`)
2. Create the `/usr/local/bin/code` symlink for easy command access
3. Install all available VS Code extensions from `.vsix` files in `/pkgs-host/`
4. Update or reinstall VS Code and extensions without rebuilding the container

## Quick Start

### Method 1: Using the PowerShell Wrapper (Recommended)

From the Windows host:

```powershell
cd C:\Users\igamenovoer\systalk\install-vscode-offline\simulate
.\deprecated\install-vscode-in-container.ps1
```

The script will:
- Check if the container is running
- Copy the installation script to the container
- Fix line endings (CRLF → LF)
- Run the installation
- Clean up temporary files

### Method 2: Manual Execution

```powershell
# 1. Copy the script to the container
podman cp helper-scripts/terminal-install-in-container.sh vscode-terminal:/tmp/

# 2. Fix line endings
podman exec vscode-terminal bash -c "sed -i 's/\r$//' /tmp/terminal-install-in-container.sh"

# 3. Make it executable
podman exec -u root vscode-terminal chmod +x /tmp/terminal-install-in-container.sh

# 4. Run it
podman exec -u root -it vscode-terminal /tmp/terminal-install-in-container.sh
```

## What Gets Installed

### VS Code Binary

- **Source**: `/pkgs-host/vscode-linux-*.tar.gz`
- **Install Location**: `/home/dev/.local/vscode/`
- **Owner**: `dev:dev`
- **Symlink**: `/usr/local/bin/code` → `/home/dev/.local/vscode/bin/code`

### Extensions

All `.vsix` files found in `/pkgs-host/` will be installed. Current extensions:

- **eamodio.gitlens** - GitLens (Git supercharged)
- **ms-python.python** - Python language support
- **ms-vscode-remote.remote-ssh** - Remote-SSH for connecting to remote servers

## Script Behavior

### First Run (VS Code Not Installed)

```
[INFO] Found VS Code tarball: vscode-linux-x64.tar.gz
[INFO] Creating installation directory...
[INFO] Extracting VS Code...
[INFO] Setting ownership to dev...
[SUCCESS] VS Code installed to /home/dev/.local/vscode
[INFO] Installed version: 1.106.2
```

### Subsequent Runs (VS Code Already Installed)

```
[WARN] VS Code is already installed at /home/dev/.local/vscode
[INFO] Installed version: 1.106.2
Reinstall? [y/N]
```

- Press **N** (default): Skips VS Code installation, but still installs/updates extensions
- Press **Y**: Removes existing VS Code and reinstalls from tarball

### Extension Installation

Extensions are installed even if VS Code installation is skipped:

```
[INFO] Found 3 extension(s) to install

[INFO] Installing: eamodio.gitlens-latest.vsix
[SUCCESS]   ✓ eamodio.gitlens-latest.vsix installed

[INFO] Installing: ms-python.python-latest.vsix
[SUCCESS]   ✓ ms-python.python-latest.vsix installed

[INFO] Installing: ms-vscode-remote.remote-ssh-latest.vsix
[SUCCESS]   ✓ ms-vscode-remote.remote-ssh-latest.vsix installed
```

## Verification

After installation, verify everything is working:

```powershell
# Check VS Code version
podman exec vscode-terminal code --version

# List installed extensions
podman exec vscode-terminal code --list-extensions

# Launch VS Code GUI
podman exec -it vscode-terminal bash -c "code --disable-gpu --no-sandbox --disable-dev-shm-usage"
```

## Troubleshooting

### "Permission denied" Error

**Problem**: Script is not executable
**Solution**:
```powershell
podman exec -u root vscode-terminal chmod +x /tmp/terminal-install-in-container.sh
```

### "required file not found" Error

**Problem**: Script has Windows line endings (CRLF)
**Solution**:
```powershell
podman exec vscode-terminal bash -c "sed -i 's/\r$//' /tmp/terminal-install-in-container.sh"
```

### "This script must be run as root"

**Problem**: Running without root privileges
**Solution**: Use `-u root` flag:
```powershell
podman exec -u root vscode-terminal /tmp/terminal-install-in-container.sh
```

### Extension Installation Fails

**Problem**: VS Code process still running or permissions issue
**Solutions**:
1. Close any running VS Code instances
2. Check file permissions on `/pkgs-host/*.vsix`
3. Verify the dev user has a proper home directory

### Container Not Found

**Problem**: Container `vscode-terminal` doesn't exist or isn't running
**Solution**: Start the container first:
```powershell
podman run -d --name vscode-terminal --shm-size=2gb \
  --network simulate_vscode-airgap-both \
  -e DISPLAY=':0' -e DONT_PROMPT_WSL_INSTALL='1' \
  -v /mnt/wslg/.X11-unix:/tmp/.X11-unix \
  -v "C:\Users\igamenovoer\systalk\install-vscode-offline\simulate\pkgs:/pkgs-host:ro" \
  -v vscode-terminal-home:/home/dev \
  localhost/vscode-airgap-terminal:latest sleep infinity
```

## Adding New Extensions

To add new extensions to be installed:

1. Download the `.vsix` file
2. Place it in `install-vscode-offline/simulate/pkgs/`
3. Re-run the installation script

The script will automatically detect and install all `.vsix` files.

## Updating VS Code

To update VS Code to a newer version:

1. Download new `vscode-linux-x64.tar.gz`
2. Place it in `install-vscode-offline/simulate/pkgs/` (replacing the old one)
3. Run the installation script
4. When prompted "Reinstall? [y/N]", press **Y**

## Script Internals

### Key Features

- **Idempotent**: Safe to run multiple times
- **Color-coded output**: Info (blue), Success (green), Warning (yellow), Error (red)
- **Smart detection**: Checks if VS Code is already installed
- **User prompts**: Asks before reinstalling existing VS Code
- **Error handling**: Captures and displays extension installation errors
- **Ownership management**: Ensures all files are owned by the `dev` user

### Directory Structure

```
/pkgs-host/                          # Host packages directory (read-only mount)
├── vscode-linux-x64.tar.gz          # VS Code tarball
├── eamodio.gitlens-latest.vsix      # GitLens extension
├── ms-python.python-latest.vsix     # Python extension
└── ms-vscode-remote.remote-ssh-latest.vsix  # Remote-SSH extension

/home/dev/.local/vscode/             # VS Code installation directory
├── bin/code                         # VS Code binary
├── resources/                       # VS Code resources
└── ...

/usr/local/bin/code                  # Symlink to VS Code binary

/home/dev/.vscode/extensions/        # Installed extensions
├── eamodio.gitlens-*/
├── ms-python.python-*/
└── ms-vscode-remote.remote-ssh-*/
```

## Use Cases

### Scenario 1: Fresh Container

You've just built the terminal image but want to install VS Code later:

```powershell
# Build container without VS Code
podman build -f terminal.Dockerfile -t vscode-airgap-terminal:latest .

# Start container
podman run -d --name vscode-terminal ... vscode-airgap-terminal:latest

# Install VS Code later
.\deprecated\install-vscode-in-container.ps1
```

### Scenario 2: Update Extensions Only

VS Code is already installed, but you want to add/update extensions:

```powershell
# Add new .vsix files to pkgs/
# Run installer (it will skip VS Code, install extensions)
.\deprecated\install-vscode-in-container.ps1
# Press 'N' when asked to reinstall VS Code
```

### Scenario 3: Complete Reinstall

You want to reinstall VS Code from scratch:

```powershell
.\deprecated\install-vscode-in-container.ps1
# Press 'Y' when asked to reinstall VS Code
```

## Integration with Container Lifecycle

### During Container Build (Dockerfile)

The terminal.Dockerfile already includes VS Code installation steps. The post-build script is useful for:
- Testing different VS Code versions without rebuilding
- Installing optional extensions
- Updating VS Code in a long-running container

### After Container Build (Post-Build Script)

Use this script when:
- You want flexibility to install/update VS Code without rebuilding
- You're testing different extension combinations
- You need to update VS Code or extensions in a production container

## Related Files

- `terminal.Dockerfile` - Builds the terminal container image with optional VS Code
- `../deprecated/install-vscode-in-container.ps1` - PowerShell wrapper for easy execution from Windows (deprecated)
- `../checks/check-terminal-docker-vscode.ps1` - Launches VS Code GUI from the container
- `../../howto-install-vscode-airgap.md` - Complete quick start guide for the airgap setup

## Next Steps

After installing VS Code and extensions:

1. **Launch VS Code GUI**:
   ```powershell
   podman exec -it vscode-terminal bash -c "code --disable-gpu --no-sandbox --disable-dev-shm-usage"
   ```

2. **Connect to Remote Server**:
   - Press `F1` → `Remote-SSH: Connect to Host...`
   - Select `vscode-remote`

3. **Verify Extensions**:
   - Check that GitLens, Python, and Remote-SSH are active
   - Open a Python file to test Python extension
   - Use Remote-SSH to connect to `vscode-remote`

4. **Start Development**!
