# Issue: VS Code GUI from Podman container does not show (X11 via WSLg works for xclock)

## Environment

- Host: Windows 10/11 with WSL2 + WSLg
- Container runtime: Podman Desktop (WSL-based `podman-machine-default`)
- Base image: `ubuntu:24.04`
- Project path: `install-vscode-offline/simulate`

## Summary

We can run X11 apps (like `xclock`) from a Podman container and see the GUI via WSLg, but running the Linux VS Code binary (`code`) from the same terminal image does not show any window, even though there are no obvious runtime errors.

## X11 wiring (working)

From the Podman machine:

- `/mnt/wslg/.X11-unix/X0` exists and is a UNIX socket owned by `user:user`.

From PowerShell, the following works and shows an xclock window:

```powershell
cd C:\Users\igamenovoer\systalk\install-vscode-offline\simulate
.\checks\check-terminal-docker-gui.ps1
```

The script effectively runs:

```powershell
podman run --rm -it `
  -e DISPLAY=:0 `
  -v /mnt/wslg/.X11-unix:/tmp/.X11-unix `
  localhost/vscode-airgap-terminal:latest `
  xclock
```

Inside the container:

- `DISPLAY=:0`
- `/tmp/.X11-unix/X0` is present
- `xclock` prints only the charset warning and the GUI appears.

## VS Code behaviour (not working)

VS Code is installed in the terminal image from `pkgs/vscode-linux-x64.tar.gz` into `/home/dev/.local/vscode`, with `/usr/local/bin/code` symlinked.

We start VS Code with:

```powershell
cd C:\Users\igamenovoer\systalk\install-vscode-offline\simulate
.\checks\check-terminal-docker-vscode.ps1
```

Which does:

```powershell
podman run --rm -it `
  --name vscode-terminal-vscode `
  --network simulate_vscode-airgap-both `
  -e DISPLAY=:0 `
  -e DONT_PROMPT_WSL_INSTALL=1 `
  -v /mnt/wslg/.X11-unix:/tmp/.X11-unix `
  -v ./pkgs:/pkgs-host:ro `
  -v vscode-terminal-home:/home/dev `
  localhost/vscode-airgap-terminal:latest `
  bash -lc 'DISPLAY=${DISPLAY:-:0} DONT_PROMPT_WSL_INSTALL=1 code --disable-gpu'
```

Observed:

- Container starts and exits when `code` terminates.
- No VS Code window appears on the host.
- Previous interactive test with `--verbose` showed Chrome/ozone `Missing X server or $DISPLAY` errors, even though `DISPLAY=:0` and X11 works for `xclock`.

## Solution (RESOLVED)

### Root Cause

The X11 connection was working correctly (as proven by `xclock`). The issue was **Chromium/Electron sandbox restrictions** and **insufficient shared memory** in the container environment.

VS Code is built on Electron (Chromium), which has strict sandboxing requirements that conflict with containerization. Specifically:
- Chromium's sandbox needs Linux capabilities not available by default in containers
- Default container `/dev/shm` size (64MB) is too small for Chromium's multiprocess architecture
- Chromium sandbox conflicts with container namespaces

### The Fix

Three changes to the `podman run` command in `check-terminal-docker-vscode.ps1`:

1. **Added `--shm-size=2gb`** (container-level fix)
   - Increases shared memory from default 64MB to 2GB
   - Chromium uses shared memory extensively for IPC between processes

2. **Added `--no-sandbox` flag** to VS Code command (application-level fix)
   - Disables Chromium's sandbox (acceptable since Podman provides container isolation)
   - Required because Linux namespaces in nested containers conflict with Chromium sandbox

3. **Added `--disable-dev-shm-usage` flag** to VS Code command (fallback fix)
   - Forces Chromium to write temp files to `/tmp` instead of `/dev/shm`
   - Additional safety measure for shared memory issues

### Updated Command

```powershell
podman run --rm -it `
  --name $containerName `
  --network $network `
  --shm-size=2gb `
  -e DISPLAY=":0" `
  -e DONT_PROMPT_WSL_INSTALL="1" `
  -v /mnt/wslg/.X11-unix:/tmp/.X11-unix `
  -v ./pkgs:/pkgs-host:ro `
  -v ${homeVolume}:/home/dev `
  $image `
  bash -lc 'DISPLAY=${DISPLAY:-:0} DONT_PROMPT_WSL_INSTALL=1 code --disable-gpu --no-sandbox --disable-dev-shm-usage --verbose'
```

### For Podman Compose

Add to service definition:

```yaml
services:
  terminal:
    shm_size: '2gb'
    command: code --disable-gpu --no-sandbox --disable-dev-shm-usage
```

### Verification

After applying the fix:
- VS Code GUI window appears via WSLg
- Verbose output shows successful Electron/Chromium initialization
- Minor dbus warnings are expected and do not affect functionality

## Notes / Open Questions (ORIGINAL)

- Is there a known issue with running the official `linux-x64` VS Code tarball under WSLg's X server from inside a Podman VM?
- Do we need additional env vars or flags (e.g. forcing X11 vs Wayland, or disabling sandbox) for VS Code in this environment?
- Any recommended way to capture more detailed logs from VS Code in this WSLg + Podman setup?

**Answer**: Yes, Chromium-based apps (including VS Code) require `--shm-size`, `--no-sandbox`, and `--disable-dev-shm-usage` to run in containers with X11 forwarding.
