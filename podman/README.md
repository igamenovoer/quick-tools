# Podman Setup for Windows

This directory contains scripts to install and configure Podman on Windows as a Docker replacement.

## Prerequisites

- Windows 10/11 with WSL2 enabled
- WinGet (App Installer) installed
- PowerShell 5.1 or later
- Administrator privileges (for some scripts)

## Before You Begin: PowerShell Execution Policy

By default, Windows may prevent running PowerShell scripts with an error like:
```
.\install-podman-engine.ps1 : File cannot be loaded because running scripts is disabled on this system.
```

### Solutions (choose one):

**Option 1: Bypass for single script (recommended for testing)**
```powershell
powershell -ExecutionPolicy Bypass -File .\install-podman-engine.ps1
```

**Option 2: Unblock downloaded scripts**
```powershell
# Unblock all scripts in current directory
Get-ChildItem *.ps1 | Unblock-File
```

**Option 3: Change execution policy for current user (permanent)**
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

**Check current execution policy:**
```powershell
Get-ExecutionPolicy -List
```

For more details, see the [PowerShell Execution Policy Troubleshooting](#powershell-execution-policy-issues) section.

## Quick Start

### 1. Install Podman Engine

**Option A: Command-line only**
```powershell
.\install-podman-engine.ps1
```

**Option B: With GUI (Podman Desktop)**
```powershell
.\install-podman-gui.ps1
```

Podman Desktop includes the Podman engine plus a graphical interface for managing containers, images, and volumes. Choose this if you prefer a GUI over command-line tools.

> **Note:** If you install Podman Desktop, you don't need to run `install-podman-engine.ps1` separately.

### 2. Initialize and Start Podman Machine

After installation, initialize and start the Podman VM:

```powershell
# Initialize a new machine (first time only)
podman machine init

# Start the machine
podman machine start

# Verify it's working
podman info
```

### 3. Install Compose Tool (Choose One)

You have two options for running Docker Compose files with Podman:

#### Option A: podman-compose (Recommended - Zero Configuration)

**Install uv (Python package manager):**
```powershell
# Install via WinGet
winget install astral-sh.uv

# Or via PowerShell script
powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"

# Verify installation
uv --version
```

**Install podman-compose via uv:**
```powershell
uv tool install podman-compose

# Verify installation
podman-compose --version
```

**Advantages:**
- ✅ Works immediately with zero configuration
- ✅ Native Podman integration (no SSH required)
- ✅ Simple and reliable
- ✅ Best for users new to Podman

**Usage:**
```powershell
podman-compose up
podman-compose down
podman-compose ps
```

#### Option B: docker-compose (Docker Compatibility Mode)

**Install Docker Compose v2 via WinGet:**
```powershell
# Install standalone Docker Compose binary
winget install Docker.DockerCompose

# Or use the provided script (installs to C:\Program Files\Docker)
.\install-docker-compose-for-podman.ps1
```

**⚠️ Additional Setup Required:** docker-compose needs SSH configuration to connect to Podman. See [Configure docker-compose for Podman](#configure-docker-compose-for-podman) below.

**Advantages:**
- ✅ Exact Docker CLI compatibility
- ✅ Familiar for Docker users
- ✅ Good for legacy workflows
- ⚠️ Requires one-time SSH setup

**Usage:**
```powershell
$env:DOCKER_HOST = "ssh://user@127.0.0.1:51325/run/user/1000/podman/podman.sock"
docker-compose up
docker-compose down
```

### 4. Enable NVIDIA GPU Support (Optional)

If you have an NVIDIA GPU and want to use it in containers:

```powershell
.\install-nvidia-runtime.ps1
```

This installs NVIDIA Container Toolkit inside the Podman machine and configures CDI (Container Device Interface).

**Prerequisites for GPU support:**
- NVIDIA GPU driver installed on Windows
- Podman machine must be running

**Test GPU access:**
```powershell
podman run --rm --device nvidia.com/gpu=all nvidia/cuda:11.0.3-base-ubuntu20.04 nvidia-smi
```

## Configure docker-compose for Podman

If you installed docker-compose (Option B above), follow these steps to make it work with Podman via SSH connection.

### Step 1: Configure SSH Authentication

Add an SSH config entry for the Podman machine:

```powershell
# Create SSH config directory if it doesn't exist
if (!(Test-Path ~/.ssh)) { mkdir ~/.ssh }

# Add Podman machine entry to SSH config
Add-Content ~/.ssh/config @"

# Podman Machine SSH Connection
Host 127.0.0.1
    HostName 127.0.0.1
    User user
    Port 51325
    IdentityFile ~/.local/share/containers/podman/machine/machine
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
"@
```

**Note:** Port `51325` is the default but may vary. Get the actual port and path from:
```powershell
podman system connection list --format json
```

### Step 2: Create docker Symlink in Podman Machine

docker-compose expects a `docker` command on the remote host. Create a symlink to `podman`:

```powershell
podman machine ssh -- 'mkdir -p ~/.local/bin && ln -sf /usr/bin/podman ~/.local/bin/docker'

# Verify it works
podman machine ssh -- 'docker --version'
# Output: docker version 5.7.0
```

### Step 3: Set DOCKER_HOST Environment Variable

docker-compose needs to know how to connect to Podman. You have three options:

#### Manual (Per-Session)

Set DOCKER_HOST each time you use docker-compose:

```powershell
$env:DOCKER_HOST = "ssh://user@127.0.0.1:51325/run/user/1000/podman/podman.sock"
docker-compose up
```

#### Automatic (PowerShell Profile)

Add to your PowerShell profile (`notepad $PROFILE`):

```powershell
# Auto-configure DOCKER_HOST for Podman
$podmanConnection = (podman system connection list --format json 2>$null | ConvertFrom-Json | Where-Object { $_.Default -eq $true })[0]
if ($podmanConnection) {
    $env:DOCKER_HOST = $podmanConnection.URI
}
```

Reload profile:
```powershell
. $PROFILE
```

#### Wrapper Script

Create `docker-compose-podman.ps1`:

```powershell
# Get default Podman connection dynamically
$connection = (podman system connection list --format json | ConvertFrom-Json | Where-Object { $_.Default -eq $true })[0]
if ($connection) {
    $env:DOCKER_HOST = $connection.URI
    & docker-compose.exe @args
} else {
    Write-Error "No default Podman connection found"
}
```

Usage:
```powershell
.\docker-compose-podman.ps1 up
.\docker-compose-podman.ps1 down
```

### Verify docker-compose Works

Test with a simple compose file:

```yaml
# test-compose.yml
services:
  hello:
    image: hello-world
```

Run:
```powershell
$env:DOCKER_HOST = "ssh://user@127.0.0.1:51325/run/user/1000/podman/podman.sock"
docker-compose -f test-compose.yml up
```

Expected output: Container runs successfully and prints "Hello from Docker!"

### GPU Support with docker-compose

For GPU access, use Podman's CDI syntax in your compose file:

```yaml
services:
  cuda-app:
    image: nvidia/cuda:11.0.3-base-ubuntu20.04
    devices:
      - nvidia.com/gpu=all
    security_opt:
      - label=disable
    command: nvidia-smi
```

Run:
```powershell
$env:DOCKER_HOST = "ssh://user@127.0.0.1:51325/run/user/1000/podman/podman.sock"
docker-compose up
```

See `howto-use-gpu-docker-compose-for-podman.md` for complete GPU usage guide.

## Docker Compatibility

### Create Docker Command Alias

To use `docker` commands instead of `podman`:

```powershell
.\make-docker-symlink.ps1
```

This creates a symbolic link `docker.exe -> podman.exe`, allowing you to use familiar Docker commands:

```powershell
docker ps
docker images
docker run hello-world
docker-compose up -d
```

### Move Podman Storage Location (Optional)

By default, Podman stores VM data in `%USERPROFILE%\.local\share\containers`. To move it to another drive:

```powershell
.\move-podman-storage-to.ps1 -TargetDir "D:\Podman"
```

Or run without parameters to be prompted for the target directory.

## Scripts Reference

| Script | Description | Admin Required |
|--------|-------------|----------------|
| `install-podman-engine.ps1` | Install Podman CLI via WinGet | No |
| `install-podman-gui.ps1` | Install Podman Desktop (GUI + engine) | No |
| `install-docker-compose-for-podman.ps1` | Install Docker Compose v2 for use with Podman | Yes |
| `install-nvidia-runtime.ps1` | Install NVIDIA Container Toolkit for GPU support | No |
| `make-docker-symlink.ps1` | Create docker.exe -> podman.exe symlink | Yes |
| `move-podman-storage-to.ps1` | Move Podman VM storage to different drive | Yes |

**Note:** For podman-compose installation, use `uv tool install podman-compose` instead (no script needed).

## Complete Setup Workflow

### Workflow 1: With podman-compose (Recommended - Simple)

```powershell
# 1. Install Podman (choose one)
.\install-podman-engine.ps1    # CLI only
# OR
.\install-podman-gui.ps1       # GUI + CLI (Podman Desktop)

# 2. Restart terminal to refresh PATH, then initialize machine
podman machine init
podman machine start

# 3. Install uv and podman-compose
winget install astral-sh.uv
uv tool install podman-compose

# 4. (Optional) Create docker alias
.\make-docker-symlink.ps1

# 5. (Optional) Move storage to another drive
.\move-podman-storage-to.ps1 -TargetDir "D:\Podman"

# 6. (Optional) Enable GPU support
.\install-nvidia-runtime.ps1

# 7. Verify setup
podman-compose --version
podman run hello-world
```

### Workflow 2: With docker-compose (Docker Compatibility)

```powershell
# 1. Install Podman (choose one)
.\install-podman-engine.ps1    # CLI only
# OR
.\install-podman-gui.ps1       # GUI + CLI (Podman Desktop)

# 2. Restart terminal to refresh PATH, then initialize machine
podman machine init
podman machine start

# 3. Install docker-compose
winget install Docker.DockerCompose
# OR
.\install-docker-compose-for-podman.ps1

# 4. Configure docker-compose for Podman
# Add SSH config
Add-Content ~/.ssh/config @"

# Podman Machine SSH Connection
Host 127.0.0.1
    User user
    Port 51325
    IdentityFile ~/.local/share/containers/podman/machine/machine
    StrictHostKeyChecking no
"@

# Create docker symlink in Podman machine
podman machine ssh -- 'mkdir -p ~/.local/bin && ln -sf /usr/bin/podman ~/.local/bin/docker'

# 5. (Optional) Create docker alias
.\make-docker-symlink.ps1

# 6. (Optional) Move storage to another drive
.\move-podman-storage-to.ps1 -TargetDir "D:\Podman"

# 7. (Optional) Enable GPU support
.\install-nvidia-runtime.ps1

# 8. Verify setup
$env:DOCKER_HOST = "ssh://user@127.0.0.1:51325/run/user/1000/podman/podman.sock"
docker-compose --version
docker run hello-world
```

## Common Commands

```powershell
# Machine management
podman machine list              # List machines
podman machine start             # Start default machine
podman machine stop              # Stop default machine
podman machine ssh               # SSH into machine

# Container operations (same as Docker)
podman run -it ubuntu bash       # Run interactive container
podman ps -a                     # List all containers
podman images                    # List images
podman pull nginx                # Pull image
podman logs <container>          # View logs

# With podman-compose (no DOCKER_HOST needed)
podman-compose up -d             # Start services in background
podman-compose down              # Stop and remove services
podman-compose ps                # List running services
podman-compose logs -f           # Follow logs

# With docker-compose (requires DOCKER_HOST)
$env:DOCKER_HOST = "ssh://user@127.0.0.1:51325/run/user/1000/podman/podman.sock"
docker-compose up -d             # Start services in background
docker-compose down              # Stop and remove services
docker-compose ps                # List running services
docker-compose logs -f           # Follow logs

# Both compose tools use the same docker-compose.yml syntax
```

## Troubleshooting

### PowerShell Execution Policy Issues

**Error:** `File cannot be loaded because running scripts is disabled on this system`

**Cause:** Windows blocks unsigned PowerShell scripts by default for security.

**Solutions:**

1. **Run with Bypass (one-time, no system changes):**
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\install-podman-engine.ps1
   ```

2. **Unblock specific files (if downloaded from internet):**
   ```powershell
   # Unblock single file
   Unblock-File .\install-podman-engine.ps1

   # Or unblock all .ps1 files in directory
   Get-ChildItem *.ps1 | Unblock-File
   ```

3. **Change policy for current user (permanent):**
   ```powershell
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
   ```
   - `RemoteSigned`: Allows local scripts, requires signature for downloaded scripts
   - `CurrentUser`: Only affects your user account, doesn't require admin

4. **Change policy for entire machine (requires admin):**
   ```powershell
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine
   ```

**Check current policies:**
```powershell
Get-ExecutionPolicy -List
```

**Recommended:** Use `RemoteSigned` for `CurrentUser` scope. This allows you to run local scripts while still protecting against potentially malicious downloaded scripts.

### "podman" command not found after installation
Restart your terminal or run:
```powershell
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
```

### Machine fails to start
```powershell
# Check WSL status
wsl --status

# Reset machine if needed
podman machine rm
podman machine init
podman machine start
```

### GPU not detected in containers
1. Ensure NVIDIA driver is installed on Windows
2. Restart the Podman machine after installing NVIDIA runtime:
   ```powershell
   podman machine stop
   podman machine start
   ```
3. Verify CDI configuration:
   ```powershell
   podman machine ssh -- nvidia-ctk cdi list
   ```

### Permission denied errors
Run the script as Administrator, or right-click PowerShell and select "Run as Administrator".

### docker-compose Connection Issues

**Error:** `Permission denied (publickey)` or `error during connect`

**Cause:** SSH authentication not configured properly.

**Solution:**
1. Add SSH config entry with correct identity file:
   ```powershell
   Add-Content ~/.ssh/config @"
   Host 127.0.0.1
       User user
       Port 51325
       IdentityFile ~/.local/share/containers/podman/machine/machine
       StrictHostKeyChecking no
   "@
   ```

2. Verify the port and socket path:
   ```powershell
   podman system connection list --format json
   ```

**Error:** `bash: docker: command not found`

**Cause:** docker symlink not created in Podman machine.

**Solution:**
```powershell
podman machine ssh -- 'mkdir -p ~/.local/bin && ln -sf /usr/bin/podman ~/.local/bin/docker'
```

**Error:** `No connection could be made because the target machine actively refused it`

**Cause:** DOCKER_HOST not set or pointing to wrong endpoint.

**Solution:**
```powershell
# Set DOCKER_HOST to SSH connection
$env:DOCKER_HOST = "ssh://user@127.0.0.1:51325/run/user/1000/podman/podman.sock"

# Or use podman-compose instead (no DOCKER_HOST needed)
uv tool install podman-compose
podman-compose up
```

### podman-compose Not Found

**Error:** `podman-compose: The term 'podman-compose' is not recognized`

**Cause:** uv tools not in PATH or not installed.

**Solution:**
```powershell
# Ensure uv tools directory is in PATH
$env:Path += ";$env:USERPROFILE\.local\bin"

# Or reinstall
uv tool install podman-compose
```

## Uninstalling

```powershell
# Stop and remove machine
podman machine stop
podman machine rm

# Uninstall Podman via WinGet
winget uninstall RedHat.Podman

# Uninstall podman-compose
uv tool uninstall podman-compose

# Uninstall docker-compose
winget uninstall Docker.DockerCompose
# OR if installed via script
Remove-Item "$env:ProgramFiles\Docker\docker-compose.exe" -Force

# Remove docker symlink (if created)
Remove-Item "$((Get-Command podman -ErrorAction SilentlyContinue).Source | Split-Path)\docker.exe" -Force

# Remove SSH config entry (optional)
# Edit ~/.ssh/config and remove the Podman Machine section

# Remove data (optional)
Remove-Item "$env:USERPROFILE\.local\share\containers" -Recurse -Force
Remove-Item "$env:USERPROFILE\.config\containers" -Recurse -Force
```

## Compose Tool Comparison

| Feature | podman-compose | docker-compose |
|---------|---------------|----------------|
| **Installation** | `uv tool install podman-compose` | `winget install Docker.DockerCompose` |
| **Configuration** | Zero config needed | Requires SSH setup |
| **DOCKER_HOST** | Not required | Required |
| **Connection Method** | Direct CLI (fork-exec) | SSH to Podman socket |
| **Setup Complexity** | Simple | Medium (SSH + symlink) |
| **Best For** | New Podman users | Docker users needing compatibility |
| **GPU Support** | ✅ CDI syntax | ✅ CDI syntax |
| **Portability** | Works across users automatically | Requires per-user SSH config |
| **Speed** | Fast (direct execution) | Slightly slower (SSH overhead) |

**Recommendation:**
- **Use podman-compose** if you're new to Podman or want simplicity
- **Use docker-compose** if you need exact Docker compatibility or have existing docker-compose workflows

Both tools use the same `docker-compose.yml` syntax and support GPU via CDI.

## Resources

- [Podman Official Site](https://podman.io/)
- [Podman Desktop](https://podman-desktop.io/)
- [uv - Python Package Manager](https://docs.astral.sh/uv/)
- [podman-compose on PyPI](https://pypi.org/project/podman-compose/)
- [Docker Compose](https://github.com/docker/compose)
- [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/)
- [GPU with Podman Guide](./howto-use-gpu-docker-compose-for-podman.md)
