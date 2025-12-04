# Docker Engine Tools

This directory contains scripts and documentation for installing and configuring Docker Engine on both Windows (via WSL2) and Linux.

## Contents

### Windows (WSL2)
Scripts for installing Docker Engine on Windows 11 without Docker Desktop.

- `install-docker-engine-wsl.ps1`: Main installation script - installs Docker Engine in WSL2 Ubuntu.
- `post-install-setup.ps1`: Post-installation configuration - user permissions, auto-start, TCP exposure.
- `howto-install-docker-without-desktop.md`: Detailed manual installation guide with GPU support.
- `setup-tcp-systemd.ps1`: Standalone script to expose Docker daemon via TCP.
- `docker-powershell-profile.ps1`: PowerShell profile snippet for Docker wrapper functions.

### Linux (Ubuntu/Debian)
Scripts for installing and managing Docker on native Linux systems.

- `install-docker.sh`: Script to install Docker Engine on Linux (Ubuntu). Handles proxy settings and repository setup.
- `add-users-to-docker.sh`: Helper script to add users to the `docker` group.

## Windows Installation Guide

### Why Use This Approach?

- **No Docker Desktop License Required** - Docker Desktop requires a license for commercial use in larger organizations
- **Lighter Weight** - Docker Engine runs directly in WSL2 without the Desktop GUI overhead
- **Full Docker Functionality** - Complete access to Docker Engine, CLI, Compose, and Buildx
- **Windows Integration** - Use Docker from both WSL and PowerShell

### Quick Start (Windows)

1. **Install Docker Engine in WSL:**
   ```powershell
   .\install-docker-engine-wsl.ps1
   ```

2. **Configure Docker for ease of use:**
   ```powershell
   .\post-install-setup.ps1 -ExposeTcp -SetWindowsDockerHost -RunTests
   ```

3. **Start using Docker:**
   ```powershell
   # From PowerShell
   wsl docker run hello-world
   ```

## Linux Installation Guide

### Install Docker

Run the installation script as root:

```bash
sudo ./install-docker.sh
```

This script will:
1. Remove conflicting packages.
2. Add Docker's official GPG key and repository.
3. Install Docker Engine, CLI, and Compose.
4. Respect `http_proxy` / `HTTP_PROXY` environment variables during installation.

### Add Users to Docker Group

To allow running Docker without `sudo`:

```bash
sudo ./add-users-to-docker.sh <username>
```

Or add all users in `/home`:

```bash
sudo ./add-users-to-docker.sh
```

## Detailed Windows Documentation

See [howto-install-docker-without-desktop.md](howto-install-docker-without-desktop.md) for a comprehensive guide on the Windows/WSL setup.
