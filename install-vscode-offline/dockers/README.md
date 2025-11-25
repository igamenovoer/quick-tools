# Docker Test Environment for VS Code Offline Installation

This Docker Compose setup provides an **isolated Ubuntu 24.04** environment with **SSH access but NO internet connectivity**, perfect for testing the VS Code offline Remote-SSH installation scripts.

## 🎯 Purpose

Test the VS Code offline installation workflow in a controlled environment that simulates an air-gapped system:
- ✅ SSH server running on Ubuntu 24.04
- ✅ No external network access (truly isolated)
- ✅ Pre-configured test user
- ✅ Port mapping for host SSH access

## 📋 Prerequisites

- Docker Desktop or Docker Engine installed
- Docker Compose installed (usually bundled with Docker Desktop)
- Windows 10/11 with PowerShell

## 🚀 Quick Start

### 1. Build and Start the Container

```powershell
cd c:\Users\igamenovoer\systalk\install-vscode-offline\dockers

# Build and start the container
docker-compose up -d

# View startup logs
docker-compose logs -f
```

### 2. Verify Container is Running

```powershell
# Check container status
docker-compose ps

# Should show:
# NAME                  STATUS    PORTS
# vscode-test-ubuntu    Up        0.0.0.0:4444->22/tcp
```

### 3. Test SSH Connection

```powershell
# Connect via SSH (you'll be prompted for password: 123456)
ssh -p 4444 testuser@localhost

# Or specify password inline (for automation)
# Note: This requires sshpass or similar tools
```

### 4. Test VS Code Server Installation

```powershell
# From the parent directory (install-vscode-offline)
cd ..

# First, download VS Code package (requires internet on host)
.\download-latest-vscode-package.ps1 -Output ".\test-package"

# Then install to the Docker container
.\install-remote.ps1 `
    -OfflinePackageDir ".\test-package" `
    -SshHost "testuser@localhost" `
    -SshPort 4444 `
    -SshPassword "123456"
```

### 5. Connect from VS Code

1. Open VS Code on your Windows host
2. Install Remote-SSH extension (if not already installed)
3. Press F1 → "Remote-SSH: Connect to Host"
4. Enter: `ssh -p 4444 testuser@localhost`
5. Enter password: `123456`
6. Select platform: Linux
7. VS Code should connect without downloading anything!

## 📦 Container Details

### Container Specifications

- **OS:** Ubuntu 24.04 LTS
- **Architecture:** x86_64 (amd64)
- **Hostname:** vscode-test
- **Container Name:** vscode-test-ubuntu

### User Credentials

- **Username:** `testuser`
- **Password:** `123456`
- **Home Directory:** `/home/testuser`
- **Sudo Access:** Yes (member of sudo group)

### Network Configuration

- **SSH Port Mapping:** Host `4444` → Container `22`
- **Network Type:** Internal bridge (isolated)
- **Internet Access:** ❌ NONE (by design)
- **Subnet:** 172.28.0.0/16 (internal only)

### Pre-installed Packages

- openssh-server
- sudo
- tar
- curl (binary present but no network access)
- ca-certificates

## 🔧 Management Commands

### Start/Stop/Restart

```powershell
# Start container
docker-compose up -d

# Stop container
docker-compose stop

# Restart container
docker-compose restart

# Stop and remove container
docker-compose down

# Stop and remove everything including volumes
docker-compose down -v
```

### View Logs

```powershell
# View all logs
docker-compose logs

# Follow logs in real-time
docker-compose logs -f

# View last 50 lines
docker-compose logs --tail=50
```

### Execute Commands in Container

```powershell
# Open bash shell as testuser
docker exec -it vscode-test-ubuntu bash

# Open bash shell as root
docker exec -it -u root vscode-test-ubuntu bash

# Run single command
docker exec vscode-test-ubuntu uname -a
```

### Check Container Status

```powershell
# Container status
docker-compose ps

# Container resource usage
docker stats vscode-test-ubuntu

# Inspect container
docker inspect vscode-test-ubuntu
```

## 🧪 Testing Scenarios

### Test 1: Basic SSH Connectivity

```powershell
# Test SSH connection
ssh -p 4444 testuser@localhost

# Expected: Successful login with password "123456"
```

### Test 2: Verify No Internet Access

```powershell
# Connect to container
ssh -p 4444 testuser@localhost

# Try to ping external host (should fail)
ping -c 3 8.8.8.8
# Expected: Network unreachable

# Try to download something (should fail)
curl https://google.com
# Expected: Connection timeout or unreachable
```

### Test 3: Install VS Code Server

```powershell
# From host, run install script
.\install-remote.ps1 `
    -OfflinePackageDir ".\test-package" `
    -SshHost "testuser@localhost" `
    -SshPort 4444 `
    -SshPassword "123456"

# Expected: Successful installation
```

### Test 4: Verify Installation

```powershell
# Connect to container
ssh -p 4444 testuser@localhost

# Check VS Code Server directory
ls -la ~/.vscode-server/cli/servers/

# Check server binary
ls -la ~/.vscode-server/cli/servers/Stable-*/server/bin/code-server

# Expected: Directory and binary exist
```

### Test 5: VS Code Remote-SSH Connection

```powershell
# Use version-check.ps1 to verify
..\version-check.ps1 -CheckRemote -SshHost "testuser@localhost" -SshPort 4444

# Then connect from VS Code
# Expected: Successful connection without downloads
```

## 🔐 SSH Configuration

### Option 1: Password Authentication (Default)

```powershell
ssh -p 4444 testuser@localhost
# Enter password: 123456
```

### Option 2: SSH Key Authentication (Recommended)

```powershell
# Generate SSH key (if you don't have one)
ssh-keygen -t ed25519 -f ~/.ssh/vscode_test_key

# Copy public key to container
Get-Content $env:USERPROFILE\.ssh\vscode_test_key.pub | ssh -p 4444 testuser@localhost "cat >> ~/.ssh/authorized_keys"

# Connect with key
ssh -p 4444 -i $env:USERPROFILE\.ssh\vscode_test_key testuser@localhost
```

### Option 3: SSH Config Entry

Create or edit `~\.ssh\config`:

```
Host vscode-test
    HostName localhost
    Port 4444
    User testuser
    IdentityFile ~/.ssh/vscode_test_key
```

Then connect simply with:

```powershell
ssh vscode-test
```

## 🐛 Troubleshooting

### Issue: Container Won't Start

**Check logs:**
```powershell
docker-compose logs
```

**Common causes:**
- Port 4444 already in use
- Docker service not running
- Insufficient resources

**Solutions:**
```powershell
# Check if port is in use
netstat -ano | findstr :4444

# Change port in docker-compose.yaml if needed
ports:
  - "5555:22"  # Use different port
```

### Issue: SSH Connection Refused

**Check if container is running:**
```powershell
docker-compose ps
```

**Check SSH service:**
```powershell
docker exec vscode-test-ubuntu pgrep -x sshd
# Should return a process ID
```

**Restart container:**
```powershell
docker-compose restart
```

### Issue: Password Authentication Fails

**Verify credentials:**
- Username: `testuser`
- Password: `123456`

**Reset password:**
```powershell
docker exec -it vscode-test-ubuntu bash -c "echo 'testuser:123456' | chpasswd"
```

### Issue: VS Code Server Installation Fails

**Check disk space:**
```powershell
docker exec vscode-test-ubuntu df -h /home/testuser
```

**Verify tar is installed:**
```powershell
docker exec vscode-test-ubuntu which tar
```

**Check permissions:**
```powershell
docker exec vscode-test-ubuntu ls -la /home/testuser/.vscode-server
```

### Issue: Container Has Internet Access

**Verify network isolation:**
```powershell
docker exec vscode-test-ubuntu ping -c 3 8.8.8.8
# Should fail with "Network unreachable"
```

**Check docker-compose.yaml:**
- Ensure `internal: true` is set in network config
- Ensure `dns: []` is set in service config

## 🎨 Customization

### Change SSH Port Mapping

Edit `docker-compose.yaml`:

```yaml
ports:
  - "5555:22"  # Change 4444 to your desired port
```

Then rebuild:
```powershell
docker-compose down
docker-compose up -d
```

### Add More Users

Edit `Dockerfile`:

```dockerfile
# Add another user
RUN useradd -m -s /bin/bash testuser2 && \
    echo 'testuser2:password123' | chpasswd
```

Rebuild:
```powershell
docker-compose build --no-cache
docker-compose up -d
```

### Increase Resources

Edit `docker-compose.yaml`:

```yaml
deploy:
  resources:
    limits:
      cpus: '4.0'      # More CPUs
      memory: 4G       # More memory
```

### Install Additional Packages

Edit `Dockerfile`:

```dockerfile
RUN apt-get update && \
    apt-get install -y \
    openssh-server \
    sudo \
    tar \
    curl \
    ca-certificates \
    git \            # Add Git
    vim \            # Add Vim
    python3 \        # Add Python
    && apt-get clean
```

## 📊 Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                       Windows Host                          │
│  ┌───────────────────────────────────────────────────────┐ │
│  │  VS Code + Remote-SSH Extension                       │ │
│  │  Port: 4444 (SSH)                                     │ │
│  └─────────────────────┬─────────────────────────────────┘ │
│                        │ SSH Connection                     │
│                        ↓                                     │
│  ┌───────────────────────────────────────────────────────┐ │
│  │  Docker Container: vscode-test-ubuntu                 │ │
│  │  ┌─────────────────────────────────────────────────┐ │ │
│  │  │  Ubuntu 24.04                                    │ │ │
│  │  │  - SSH Server (Port 22)                          │ │ │
│  │  │  - User: testuser / Password: 123456             │ │ │
│  │  │  - VS Code Server Location:                      │ │ │
│  │  │    ~/.vscode-server/cli/servers/                 │ │ │
│  │  │                                                   │ │ │
│  │  │  Network: ISOLATED (no internet)                 │ │ │
│  │  │  Subnet: 172.28.0.0/16 (internal only)           │ │ │
│  │  └─────────────────────────────────────────────────┘ │ │
│  └───────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

## 🔗 Integration with Installation Scripts

### Complete Workflow

```powershell
# 1. Start Docker test environment
cd dockers
docker-compose up -d

# 2. Download VS Code package (host has internet)
cd ..
.\download-latest-vscode-package.ps1 -Output ".\test-package"

# 3. Install VS Code Server to container (offline)
.\install-remote.ps1 `
    -OfflinePackageDir ".\test-package" `
    -SshHost "testuser@localhost" `
    -SshPort 4444 `
    -SshPassword "123456"

# 4. Verify installation
.\version-check.ps1 `
    -CheckLocal `
    -CheckRemote `
    -SshHost "testuser@localhost"

# 5. Connect from VS Code
# F1 → Remote-SSH: Connect to Host → ssh -p 4444 testuser@localhost
```

## 📝 Notes

- **Network Isolation:** The container has NO internet access by design. This simulates a true air-gapped environment.
- **Security:** Uses password authentication for testing. In production, use SSH keys.
- **Persistence:** Container data is ephemeral unless volumes are added.
- **Performance:** Container is limited to 2 CPU cores and 2GB RAM by default.
- **Architecture:** Container runs x86_64 (amd64) architecture.

## 🧹 Cleanup

### Remove Everything

```powershell
# Stop and remove container
docker-compose down

# Remove images
docker-compose down --rmi all

# Remove volumes (if any)
docker-compose down -v

# Complete cleanup
docker-compose down -v --rmi all
docker system prune -af
```

## 📚 References

- [Docker Compose Documentation](https://docs.docker.com/compose/)
- [OpenSSH Server Configuration](https://www.openssh.com/)
- [VS Code Remote-SSH](https://code.visualstudio.com/docs/remote/ssh)
- Parent README: `../README.md`

## ✅ Ready to Test!

Your isolated Ubuntu 24.04 SSH test environment is ready. Start the container with:

```powershell
docker-compose up -d
```

Then follow the testing scenarios above to validate your VS Code offline installation scripts!
