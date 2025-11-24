# Podman Setup Guide - Recent Updates

## What's New

### Comprehensive Compose Setup Guide

The README now includes detailed instructions for both compose tools:

#### 1. podman-compose (Recommended - Simple)
- **Installation via uv**: Complete instructions for installing uv (Python package manager)
- **Zero configuration**: Works immediately after installation
- **Best for**: New Podman users, simple workflows

**Quick Setup:**
```powershell
winget install astral-sh.uv
uv tool install podman-compose
podman-compose up
```

#### 2. docker-compose (Docker Compatibility)
- **Installation via WinGet**: `winget install Docker.DockerCompose`
- **SSH Configuration**: Complete guide for setting up SSH authentication
- **docker Symlink**: Instructions to create docker command in Podman machine
- **DOCKER_HOST Setup**: Three options (manual, profile, wrapper script)
- **Best for**: Docker users needing exact CLI compatibility

**Setup Highlights:**
```powershell
# 1. Install
winget install Docker.DockerCompose

# 2. SSH Config (one-time)
Add-Content ~/.ssh/config @"
Host 127.0.0.1
    User user
    Port 51325
    IdentityFile ~/.local/share/containers/podman/machine/machine
"@

# 3. Create docker symlink in Podman machine
podman machine ssh -- 'mkdir -p ~/.local/bin && ln -sf /usr/bin/podman ~/.local/bin/docker'

# 4. Use with DOCKER_HOST
$env:DOCKER_HOST = "ssh://user@127.0.0.1:51325/run/user/1000/podman/podman.sock"
docker-compose up
```

### New Sections

1. **Configure docker-compose for Podman**
   - Step-by-step SSH authentication setup
   - docker symlink creation
   - Three DOCKER_HOST configuration methods
   - GPU support with CDI syntax
   - Verification steps

2. **Complete Setup Workflows**
   - Workflow 1: With podman-compose (simple)
   - Workflow 2: With docker-compose (Docker compatibility)
   - Both include GPU support and storage options

3. **Updated Common Commands**
   - podman-compose examples (no DOCKER_HOST needed)
   - docker-compose examples (with DOCKER_HOST)
   - Clear distinction between the two tools

4. **Enhanced Troubleshooting**
   - docker-compose connection issues
   - SSH authentication problems
   - docker symlink errors
   - podman-compose PATH issues

5. **Compose Tool Comparison Table**
   - Feature-by-feature comparison
   - Installation complexity
   - Configuration requirements
   - Use case recommendations

## Key Improvements

### User-Friendly
- Clear choice between two compose tools
- Detailed pros/cons for each option
- Step-by-step configuration guides
- Multiple automation options

### Docker Compatibility
- Complete docker-compose setup guide
- SSH-based connection to Podman
- Dynamic configuration options
- Legacy workflow support

### GPU Support
- Documented for both tools
- CDI syntax examples
- Link to comprehensive GPU guide

### Troubleshooting
- Specific error messages and solutions
- Clear cause and resolution steps
- Alternative approaches provided

## Documentation Structure

```
quick-tools/podman/
├── README.md (UPDATED - comprehensive guide)
├── install-podman-engine.ps1
├── install-podman-gui.ps1
├── install-docker-compose-for-podman.ps1 (renamed from install-podman-compose.ps1)
├── install-nvidia-runtime.ps1
├── make-docker-symlink.ps1
├── move-podman-storage-to.ps1
├── howto-use-gpu-docker-compose-for-podman.md
└── CHANGELOG.md (this file)
```

## Related Documentation

- **GPU Test Results**: `tmp/gpu-test/TEST-RESULTS.md`
- **docker-compose Setup Guide**: `tmp/gpu-test/DOCKER-COMPOSE-PODMAN-SETUP.md`
- **GPU Usage Guide**: `quick-tools/podman/howto-use-gpu-docker-compose-for-podman.md`

## Summary

The README now provides:
1. ✅ Complete uv installation instructions
2. ✅ podman-compose setup via uv (recommended)
3. ✅ docker-compose setup via winget (compatibility mode)
4. ✅ SSH configuration for docker-compose
5. ✅ Two complete workflow options
6. ✅ Comprehensive troubleshooting
7. ✅ Clear comparison and recommendations

Both compose tools are fully documented and ready to use!
