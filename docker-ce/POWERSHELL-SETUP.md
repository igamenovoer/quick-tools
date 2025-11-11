# Docker PowerShell Setup - Quick Reference

## What Was Created

1. **`setup-docker-powershell.ps1`** - Main setup script for Docker CLI in PowerShell
2. **`test-docker-powershell.ps1`** - Test script to verify Docker works from PowerShell
3. **PowerShell Profile** - Updated with Docker wrapper functions at:
   `C:\Users\igamenovoer\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1`

## Setup Methods

### Method 1: Wrapper Functions (Recommended - Already Configured ✓)

**Pros:**
- Fast and lightweight
- No additional software needed
- Works immediately after profile reload
- No security concerns

**How it works:**
```powershell
# These functions are now in your PowerShell profile:
function docker { wsl -d Ubuntu docker @args }
function docker-compose { wsl -d Ubuntu docker compose @args }
```

### Method 2: Native Docker CLI

**Pros:**
- Native Windows experience
- Direct binary execution
- Works with other Windows tools

**Requires:**
- Docker daemon exposed via TCP (already configured ✓)
- Windows Docker CLI installed

**To enable:**
```powershell
.\setup-docker-powershell.ps1 -Method Native
# Or install CLI manually:
winget install Docker.DockerCLI
```

## Usage

### Current Setup (After Profile Reload)

```powershell
# Restart PowerShell or run:
. $PROFILE

# Now use Docker naturally:
docker ps
docker run -d nginx
docker compose up -d
docker images
docker logs container_name
```

### All Available Commands

```powershell
# Container management
docker ps                          # List running containers
docker ps -a                       # List all containers
docker run -d nginx                # Run container in background
docker stop container_name         # Stop container
docker rm container_name           # Remove container
docker logs -f container_name      # Follow logs

# Image management
docker images                      # List images
docker pull ubuntu                 # Pull image
docker rmi image_name              # Remove image
docker build -t myapp .            # Build image

# Docker Compose
docker compose up -d               # Start services in background
docker compose down                # Stop and remove services
docker compose ps                  # List services
docker compose logs -f             # Follow logs

# System
docker system df                   # Show disk usage
docker system prune -a             # Clean up everything (use with caution)
docker info                        # Show Docker system info
```

## Verification

Run the test script anytime:
```powershell
.\test-docker-powershell.ps1
```

## Troubleshooting

### "docker: command not found" in new PowerShell window

**Solution:** Reload your profile
```powershell
. $PROFILE
```

Or restart PowerShell to load it automatically.

### Docker commands are slow

**Normal:** Wrapper functions add ~50-100ms overhead due to WSL invocation.
For faster performance, use native Docker CLI or run commands directly in WSL.

### Want to use native Docker CLI

**Requirements:**
1. Install Docker CLI: `winget install Docker.DockerCLI`
2. Ensure TCP is exposed (already done ✓)
3. Restart PowerShell to load DOCKER_HOST environment variable

## Files Modified

- **PowerShell Profile:** `$PROFILE`
  - Added docker wrapper functions
  - Automatically loaded when PowerShell starts

- **Windows Environment Variables:**
  - `DOCKER_HOST=tcp://127.0.0.1:2375` (for native CLI)

## Uninstall

To remove Docker wrapper functions:
```powershell
notepad $PROFILE
# Delete the lines between:
# "# Docker CLI wrapper functions" and the blank line after
```

To remove DOCKER_HOST:
```powershell
[System.Environment]::SetEnvironmentVariable('DOCKER_HOST', $null, 'User')
```

## Next Steps

1. **Restart PowerShell** (or run `. $PROFILE`)
2. **Test:** `docker ps`
3. **Run your first container:** `docker run -d -p 80:80 nginx`
4. **Check it:** `docker ps` and visit http://localhost

Enjoy using Docker from PowerShell! 🐳
