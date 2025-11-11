# post-install-setup.ps1 - Updated Usage Guide

## Summary of Changes

The `post-install-setup.ps1` script has been updated with a new `-PowerShellMethod` parameter that controls how Docker is accessed from PowerShell.

## PowerShell Access Methods

### Default: NativeCLI (Recommended)

```powershell
.\post-install-setup.ps1
```

**What it does:**
- ✅ Exposes Docker daemon via TCP (port 2375)
- ✅ Sets DOCKER_HOST environment variable
- ✅ Installs Windows Docker CLI via winget
- ✅ Enables native `docker` and `docker compose` commands in PowerShell

**After setup:**
```powershell
# Restart PowerShell, then use Docker natively
docker ps
docker run -d nginx
docker compose up -d
```

### Method: Wrapper

```powershell
.\post-install-setup.ps1 -PowerShellMethod Wrapper
```

**What it does:**
- ✅ Adds wrapper functions to PowerShell profile
- ✅ No TCP exposure needed (more secure)
- ✅ No additional software installation

**After setup:**
```powershell
# Restart PowerShell or run: . $PROFILE
docker ps          # Executes: wsl docker ps
docker-compose up  # Executes: wsl docker compose up
```

### Method: Both

```powershell
.\post-install-setup.ps1 -PowerShellMethod Both
```

**What it does:**
- ✅ Installs native Docker CLI
- ✅ Adds wrapper functions
- ✅ Gives you both options

### Method: None

```powershell
.\post-install-setup.ps1 -PowerShellMethod None
```

**What it does:**
- Only configures user group and auto-start
- Skips all PowerShell integration
- Use `wsl docker` commands manually

## All Parameters

```powershell
.\post-install-setup.ps1 `
  -Distro Ubuntu `              # WSL distribution (default: Ubuntu)
  -PowerShellMethod NativeCLI ` # Access method (default: NativeCLI)
  -TcpPort 2375 `              # TCP port (default: 2375)
  -SkipUserGroup `             # Skip adding user to docker group
  -SkipAutoStart `             # Skip enabling auto-start
  -SkipCLIInstall `            # Skip Docker CLI installation
  -RunTests                    # Run verification tests
```

## Common Usage Examples

### Fresh Installation (Recommended)
```powershell
# Complete setup with default NativeCLI method
.\post-install-setup.ps1 -RunTests
```

### Lightweight Setup
```powershell
# Use wrapper functions only (no CLI install)
.\post-install-setup.ps1 -PowerShellMethod Wrapper -RunTests
```

### Both Methods Available
```powershell
# Setup both native CLI and wrapper functions
.\post-install-setup.ps1 -PowerShellMethod Both -RunTests
```

### Just Core Configuration
```powershell
# Only user group + auto-start, no PowerShell integration
.\post-install-setup.ps1 -PowerShellMethod None
```

### Reconfigure Existing Setup
```powershell
# Switch from wrapper to native CLI
.\post-install-setup.ps1 -PowerShellMethod NativeCLI -SkipUserGroup -SkipAutoStart
```

## Comparison: NativeCLI vs Wrapper

| Feature | NativeCLI | Wrapper |
|---------|-----------|---------|
| **Performance** | Native Windows binary | ~50-100ms overhead (WSL call) |
| **Installation** | Requires Docker CLI install | No additional software |
| **Security** | Requires TCP exposure | Direct WSL, no TCP |
| **Compatibility** | Works with all Windows tools | Works everywhere |
| **Setup Time** | ~1-2 minutes | ~5 seconds |
| **Best For** | Regular Docker users | Occasional use, security-conscious |

## Testing Your Setup

After setup, test immediately:
```powershell
# Works immediately (no restart needed)
wsl docker ps

# After restarting PowerShell (wrapper method)
. $PROFILE
docker ps

# After restarting PowerShell (native CLI method)
docker ps
docker version
docker compose version
```

## Troubleshooting

### "docker: command not found" (Native CLI)

**Solution:** Restart PowerShell completely
```powershell
# Close and reopen PowerShell
docker --version
```

### "docker: command not found" (Wrapper)

**Solution:** Reload profile
```powershell
. $PROFILE
docker ps
```

### TCP Connection Refused

**Solution:** Check Docker is listening
```powershell
wsl -d Ubuntu bash -c "ss -tlnp | grep 2375"
# Should show Docker listening on port 2375
```

## Migration Guide

### From Wrapper to NativeCLI
```powershell
.\post-install-setup.ps1 -PowerShellMethod NativeCLI -SkipUserGroup -SkipAutoStart
# Restart PowerShell
```

### From NativeCLI to Wrapper
```powershell
.\post-install-setup.ps1 -PowerShellMethod Wrapper -SkipUserGroup -SkipAutoStart
# Wrapper functions will override but both will work
```

## What Changed

**Old behavior:**
- Required explicit `-ExposeTcp -SetWindowsDockerHost` flags
- No automatic CLI installation
- Manual profile setup needed

**New behavior:**
- Single `-PowerShellMethod` parameter
- Automatic CLI installation (default)
- Integrated profile setup
- Smarter defaults for common use cases

## Backward Compatibility

Old command style still works:
```powershell
# Old style (still works)
.\post-install-setup.ps1 -ExposeTcp -SetWindowsDockerHost

# New equivalent
.\post-install-setup.ps1 -PowerShellMethod NativeCLI
```

---

**Last Updated:** 2025-01-11
**Default Method:** NativeCLI (installs Docker CLI + Compose)
