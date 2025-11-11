# Docker Engine for Windows 11 (without Docker Desktop)

This directory contains scripts and documentation for installing and configuring **Docker Engine (Community Edition)** on Windows 11 using **WSL2**, without requiring Docker Desktop.

## Why Use This Approach?

- **No Docker Desktop License Required** - Docker Desktop requires a license for commercial use in larger organizations
- **Lighter Weight** - Docker Engine runs directly in WSL2 without the Desktop GUI overhead
- **Full Docker Functionality** - Complete access to Docker Engine, CLI, Compose, and Buildx
- **Windows Integration** - Use Docker from both WSL and PowerShell

## Quick Start

### Prerequisites

- Windows 11 (any edition)
- Administrator access for initial WSL installation
- Internet connection

### Installation (5 minutes)

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

   # Or open WSL
   wsl
   docker ps
   ```

That's it! Docker Engine is now installed and ready to use.

## What's Included

| File | Description |
|------|-------------|
| `install-docker-engine-wsl.ps1` | Main installation script - installs Docker Engine in WSL2 Ubuntu |
| `post-install-setup.ps1` | Post-installation configuration - user permissions, auto-start, TCP exposure |
| `howto-install-docker-without-desktop.md` | Detailed manual installation guide with GPU support |
| `setup-tcp-systemd.ps1` | Standalone script to expose Docker daemon via TCP |
| `docker-powershell-profile.ps1` | PowerShell profile snippet for Docker wrapper functions |

## Detailed Installation Guide

### Step 1: Install Docker Engine

The main installation script automates the entire process:

```powershell
# Basic installation (installs in Ubuntu distro)
.\install-docker-engine-wsl.ps1

# With all options
.\install-docker-engine-wsl.ps1 -Distro Ubuntu -InstallDistro -ExposeTcp -SetWindowsDockerHost -RunHelloWorld
```

**What it does:**
- ✓ Installs WSL2 + Ubuntu (if needed)
- ✓ Enables systemd in WSL
- ✓ Installs Docker Engine, CLI, Compose, and Buildx
- ✓ Configures Docker daemon
- ✓ Optionally exposes Docker via TCP for Windows access

**Parameters:**
- `-Distro` - WSL distribution name (default: Ubuntu)
- `-InstallDistro` - Auto-install WSL distro if missing (requires admin)
- `-ExposeTcp` - Expose Docker daemon on TCP port
- `-TcpPort` - TCP port number (default: 2375)
- `-SetWindowsDockerHost` - Set Windows DOCKER_HOST environment variable
- `-RunHelloWorld` - Test installation with hello-world container

### Step 2: Post-Installation Setup

Configure Docker for optimal usability:

```powershell
# Recommended setup
.\post-install-setup.ps1 -ExposeTcp -SetWindowsDockerHost -RunTests

# Minimal setup (just user permissions + auto-start)
.\post-install-setup.ps1

# Custom TCP port
.\post-install-setup.ps1 -ExposeTcp -TcpPort 2376 -SetWindowsDockerHost
```

**What it does:**
- ✓ Adds your user to docker group (run without sudo)
- ✓ Enables Docker to start automatically with WSL
- ✓ (Optional) Exposes Docker daemon via TCP for PowerShell access
- ✓ (Optional) Sets Windows environment variables
- ✓ (Optional) Runs comprehensive tests

**Parameters:**
- `-ExposeTcp` - Expose Docker daemon on TCP
- `-TcpPort` - TCP port (default: 2375)
- `-SetWindowsDockerHost` - Set DOCKER_HOST environment variable
- `-SkipUserGroup` - Skip adding user to docker group
- `-SkipAutoStart` - Skip enabling auto-start
- `-RunTests` - Run Docker verification tests

## Using Docker

### Option 1: From WSL (Recommended)

```bash
# Open WSL
wsl

# Use Docker normally
docker ps
docker run -d nginx
docker compose up
```

### Option 2: From PowerShell (via WSL wrapper)

Add to your PowerShell profile (`notepad $PROFILE`):

```powershell
function docker { wsl docker @args }
function docker-compose { wsl docker compose @args }
```

Then use Docker from PowerShell:

```powershell
docker ps
docker run -d nginx
docker compose up -d
```

### Option 3: Native Windows Docker CLI (via TCP)

If you ran `post-install-setup.ps1 -ExposeTcp -SetWindowsDockerHost`:

1. Install Windows Docker CLI:
   ```powershell
   winget install Docker.DockerCLI
   ```

2. Restart PowerShell

3. Use Docker natively:
   ```powershell
   docker ps
   docker run hello-world
   ```

   The CLI automatically connects to `tcp://127.0.0.1:2375` via `DOCKER_HOST`.

## Common Tasks

### Start/Stop Docker

```bash
# In WSL
sudo systemctl start docker
sudo systemctl stop docker
sudo systemctl restart docker
sudo systemctl status docker
```

### Check Docker Status

```bash
# In WSL
docker version
docker info
docker ps
```

### Update Docker

```bash
# In WSL
sudo apt-get update
sudo apt-get install --only-upgrade docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

### Remove Docker

```bash
# In WSL
sudo apt-get purge docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo rm -rf /var/lib/docker
sudo rm -rf /etc/docker
```

## Advanced Topics

### GPU Support (NVIDIA)

For machine learning and GPU-accelerated containers, see the **NVIDIA GPU Support** section in `howto-install-docker-without-desktop.md`.

**Quick setup:**
```bash
# In WSL (after installing NVIDIA Windows driver)
# Install NVIDIA Container Toolkit
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
  sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
  sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

sudo apt-get update
sudo apt-get install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker

# Test GPU access
docker run --rm --gpus all nvidia/cuda:12.4.0-base-ubuntu22.04 nvidia-smi
```

### Custom Daemon Configuration

If you need to customize Docker daemon settings (other than TCP exposure):

```bash
# In WSL
sudo nano /etc/docker/daemon.json
```

Example configuration:
```json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "default-address-pools": [
    {
      "base": "172.17.0.0/16",
      "size": 24
    }
  ]
}
```

**Important:** If Docker is managed by systemd and you've configured TCP via systemd override, do **NOT** add `"hosts"` to `daemon.json` (it will conflict).

After editing:
```bash
sudo systemctl restart docker
```

### Multiple WSL Distros

You can install Docker in multiple WSL distributions:

```powershell
# Install in Ubuntu
.\install-docker-engine-wsl.ps1 -Distro Ubuntu

# Install in Debian
.\install-docker-engine-wsl.ps1 -Distro Debian

# Configure both
.\post-install-setup.ps1 -Distro Ubuntu
.\post-install-setup.ps1 -Distro Debian
```

## Troubleshooting

### Docker daemon not starting

```bash
# Check Docker service status
sudo systemctl status docker

# Check logs
sudo journalctl -xeu docker.service

# Common fix: restart WSL
# In PowerShell:
wsl --shutdown
wsl
```

### Permission denied when running docker

```bash
# Ensure you're in docker group
groups

# If docker group is missing, run:
sudo usermod -aG docker $USER

# Then log out and back in, or run:
newgrp docker
```

### TCP connection fails from Windows

```bash
# In WSL, check if Docker is listening on TCP
sudo netstat -tlnp | grep 2375
# Or
sudo ss -tlnp | grep 2375

# If not listening, reconfigure:
```
```powershell
# In PowerShell
.\post-install-setup.ps1 -ExposeTcp -SetWindowsDockerHost
```

### "hosts" configuration conflict error

If you see:
```
the following directives are specified both as a flag and in the configuration file: hosts
```

**Solution:**
```bash
# Remove conflicting daemon.json
sudo rm -f /etc/docker/daemon.json
sudo systemctl daemon-reload
sudo systemctl restart docker
```

The correct way to expose TCP when systemd manages Docker is via systemd override (which our scripts do automatically).

### WSL networking issues

```powershell
# Reset WSL networking
wsl --shutdown
# Wait 8 seconds, then restart:
wsl
```

### Docker containers can't access internet

```bash
# Check DNS in container
docker run --rm busybox nslookup google.com

# If failing, configure DNS in daemon.json:
sudo tee /etc/docker/daemon.json > /dev/null <<EOF
{
  "dns": ["8.8.8.8", "8.8.4.4"]
}
EOF

sudo systemctl restart docker
```

## Performance Tips

### Use Linux filesystem for better performance

Store your code in the Linux filesystem (`~/projects`) rather than Windows filesystem (`/mnt/c/...`):

```bash
# Good (fast)
cd ~/projects
git clone https://github.com/user/repo.git
cd repo
docker compose up

# Avoid (slow)
cd /mnt/c/Users/YourName/projects
```

The Linux filesystem is **significantly faster** for Docker volume mounts and file I/O.

### Limit Docker resource usage (optional)

Create `%USERPROFILE%\.wslconfig`:

```ini
[wsl2]
memory=8GB        # Limits WSL2 memory
processors=4      # Limits WSL2 CPU cores
swap=2GB          # Limits swap size
```

Restart WSL after editing:
```powershell
wsl --shutdown
```

## Security Considerations

### TCP Exposure Without TLS

⚠️ **Warning:** Exposing Docker daemon via TCP without TLS is **insecure**.

Our scripts bind to `127.0.0.1` (localhost only), which is relatively safe on a single-user machine. However:

- **Do not** bind to `0.0.0.0` (all interfaces)
- **Do not** expose port 2375 through Windows Firewall
- **Consider** setting up TLS if you need remote access (see [Docker docs](https://docs.docker.com/engine/security/protect-access/))

### Docker Group Privileges

Users in the `docker` group have **root-equivalent access** to the system because they can:
- Mount any directory into a container
- Run containers with host network mode
- Access host files via volumes

Only add trusted users to the docker group.

## Resources

- **[Docker Engine Installation Guide](howto-install-docker-without-desktop.md)** - Detailed manual installation guide
- [Docker Official Documentation](https://docs.docker.com/)
- [Docker Engine on Ubuntu](https://docs.docker.com/engine/install/ubuntu/)
- [WSL Documentation](https://learn.microsoft.com/en-us/windows/wsl/)
- [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/)

## Support

If you encounter issues:

1. Check the **Troubleshooting** section above
2. Review `howto-install-docker-without-desktop.md` for detailed explanations
3. Check Docker service logs: `sudo journalctl -xeu docker.service`
4. Verify WSL is up to date: `wsl --update`

## Contributing

Improvements and bug fixes welcome! Please test thoroughly on Windows 11 before submitting changes.

## License

These scripts and documentation are provided as-is for educational and practical use. Docker Engine itself is licensed under Apache 2.0.

---

**Last Updated:** 2025-01-11
**Tested On:** Windows 11 with WSL2 + Ubuntu 24.04
**Docker Version:** 29.0.0
