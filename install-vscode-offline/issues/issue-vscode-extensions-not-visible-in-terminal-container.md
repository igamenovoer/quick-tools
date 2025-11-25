# Issue: Preinstalled VS Code Extensions Not Visible in Terminal Container GUI

## Environment

- Host: Windows 10/11 with WSL2 + WSLg
- Container runtime: Podman Desktop (WSL-based `podman-machine-default`)
- Base image: `ubuntu:24.04`
- Project path: `install-vscode-offline/simulate`
- Terminal image: `localhost/vscode-airgap-terminal:latest`
- Default user inside terminal container: `vscode-tester`

## Expected Behavior

The terminal Docker image is built so that VS Code and extensions are fully preinstalled for the `vscode-tester` user:

- VS Code binary at:
  - `/home/vscode-tester/.local/vscode/bin/code` (symlinked to `/usr/local/bin/code`)
- Extensions unzipped at:
  - `/home/vscode-tester/.vscode/extensions`

When VS Code GUI is started inside the container as `vscode-tester` (via `launch-vscode-in-terminal-container.ps1`), the Extensions view in the UI should show:

- GitLens
- Python
- Remote-SSH
- Cline (Claude Dev)
- Markdown Preview Enhanced

## Actual Behavior

- On disk, after image build and container start:

  ```bash
  # inside container (podman exec), as vscode-tester
  ls -1 /home/vscode-tester/.vscode/extensions
  ```

  shows:

  - `eamodio.gitlens-latest`
  - `ms-python.python-latest`
  - `ms-vscode-remote.remote-ssh-latest`
  - `saoudrizwan.claude-dev-openvsx`
  - `shd101wyy.markdown-preview-enhanced-openvsx`

  These directories were created during `terminal.Dockerfile` build by unzipping `.vsix` files from `simulate/pkgs/extensions`.

- However, when VS Code GUI is launched via:

  ```powershell
  cd install-vscode-offline/simulate
  .\start-both.ps1 -Yes
  .\launch-vscode-in-terminal-container.ps1
  ```

  the Extensions view inside the VS Code UI does **not** show these extensions as installed. The user experience is “clean” VS Code with no visible extensions, despite the files being present under `~/.vscode/extensions`.

## Reproduction Steps

This section outlines the exact steps another developer can follow to reproduce the issue.

### 1. Prerequisites on Host

From the repo root (`C:\Users\<user>\systalk`):

1. Ensure the following are installed on the host:
   - Podman Desktop (with a WSL‑based Podman machine).
   - WSL2 with WSLg enabled (`wsl xclock` should display a window).
   - `ovsx` CLI (for Open VSX):

     ```bash
     npm install -g ovsx
     ```

2. Populate `simulate/pkgs`:
   - Place `vscode-linux-x64-*.tar.gz` in `install-vscode-offline/simulate/pkgs/terminal`.
   - Place VS Code Server tarballs in `install-vscode-offline/simulate/pkgs/server`.

3. Download extensions (online machine, then copy into repo):

   ```bash
   cd C:\Users\<user>\systalk\install-vscode-offline\simulate\pkgs\extensions

   ovsx get eamodio.gitlens -o eamodio.gitlens-latest.vsix
   ovsx get ms-python.python -o ms-python.python-latest.vsix
   ovsx get ms-vscode-remote.remote-ssh -o ms-vscode-remote.remote-ssh-latest.vsix
   ovsx get saoudrizwan.claude-dev -o saoudrizwan.claude-dev-openvsx.vsix
   ovsx get shd101wyy.markdown-preview-enhanced -o shd101wyy.markdown-preview-enhanced-openvsx.vsix
   ```

   Verify each `.vsix` is a valid ZIP (optional, but recommended):

   ```bash
   python -c "import os,zipfile,sys;base=r'install-vscode-offline/simulate/pkgs/extensions';
for n in os.listdir(base):
  p=os.path.join(base,n)
  (zipfile.ZipFile(p).testzip(),zipfile.ZipFile(p).close()) if n.endswith('.vsix') else None"
   ```

### 2. Build Terminal Image

From the repo root:

```powershell
cd C:\Users\<user>\systalk
install-vscode-offline\simulate\build-terminal-docker.ps1 -NoCache
```

This should produce `localhost/vscode-airgap-terminal:latest` and log:

- `==> VS Code <version> installed successfully`
- `==> Extensions installed under /home/vscode-tester/.vscode/extensions`

### 3. Start Both Containers (Terminal + Server)

```powershell
cd C:\Users\<user>\systalk\install-vscode-offline\simulate
.\start-both.ps1 -Yes
```

This:

- Creates/ensures internal network `vscode-airgap-both` (no internet).
- Starts:
  - `vscode-terminal` using `localhost/vscode-airgap-terminal:latest`
  - `vscode-remote` using `localhost/vscode-airgap-server:latest`

Confirm:

```powershell
podman ps
```

should list both containers as `Up`.

### 4. Confirm Extensions Are on Disk

Inside the terminal container:

```powershell
podman exec -it --user vscode-tester vscode-terminal bash

ls -1 ~/.vscode/extensions
```

Expected output:

- `eamodio.gitlens-latest`
- `ms-python.python-latest`
- `ms-vscode-remote.remote-ssh-latest`
- `saoudrizwan.claude-dev-openvsx`
- `shd101wyy.markdown-preview-enhanced-openvsx`

Exit the container shell.

### 5. Launch VS Code GUI

From `install-vscode-offline\simulate`:

```powershell
.\launch-vscode-in-terminal-container.ps1
```

This:

- Attaches to `vscode-terminal` as `vscode-tester`.
- Runs:

  ```bash
  DISPLAY=${DISPLAY:-:0} DONT_PROMPT_WSL_INSTALL=1 code --disable-gpu --no-sandbox --disable-dev-shm-usage --verbose
  ```

- A VS Code window should appear via WSLg on the host.

### 6. Observe Extensions in the GUI

In the VS Code window:

1. Open the Extensions view (`Ctrl+Shift+X`).
2. Expected (ideal) behavior:
   - GitLens, Python, Remote‑SSH, Cline (Claude Dev), Markdown Preview Enhanced appear as installed.
3. Actual behavior (current issue):
   - None of these extensions show up as installed; the list appears empty or only shows built‑in extensions, even though the extension folders exist under `~/.vscode/extensions`.

## Relevant Implementation Details

### 1. Extension Installation in Dockerfile

In `simulate/terminal.Dockerfile`, after copying `pkgs/extensions` into the image:

- We install system tools, including `unzip`.
- We copy `.vsix` files:

```dockerfile
COPY pkgs/extensions/ /pkgs-extensions/
```

- We install extensions by manually unzipping each `.vsix`:

```dockerfile
ARG SSH_USERNAME
RUN set -eux; \
    EXT_DIR="/home/${SSH_USERNAME}/.vscode/extensions"; \
    mkdir -p "${EXT_DIR}"; \
    if ls /pkgs-extensions/*.vsix >/dev/null 2>&1; then \
        echo "==> Installing VS Code extensions from /pkgs-extensions (manual unzip)"; \
        EXTENSION_COUNT=$(ls /pkgs-extensions/*.vsix | wc -l); \
        echo "==> Found ${EXTENSION_COUNT} extension(s)"; \
        for VSIX in /pkgs-extensions/*.vsix; do \
            VSIX_BASENAME=$(basename "${VSIX}"); \
            EXT_NAME="${VSIX_BASENAME%.vsix}"; \
            TARGET_DIR="${EXT_DIR}/${EXT_NAME}"; \
            echo "==> Installing: ${VSIX_BASENAME} -> ${TARGET_DIR}"; \
            rm -rf "${TARGET_DIR}"; \
            mkdir -p "${TARGET_DIR}"; \
            unzip -q "${VSIX}" -d "${TARGET_DIR}"; \
        done; \
        chown -R "${SSH_USERNAME}:${SSH_USERNAME}" "${EXT_DIR}"; \
        echo "==> Extensions installed under ${EXT_DIR}"; \
    else \
        echo "==> No .vsix extension files found in /pkgs-extensions"; \
        echo "==> VS Code will run without extensions"; \
    fi
```

This matches VS Code’s default extension lookup directory on Linux: `~/.vscode/extensions`.

### 2. Launching VS Code in the Container

`simulate/launch-vscode-in-terminal-container.ps1` launches VS Code GUI as `vscode-tester` without overriding the extensions directory:

```powershell
podman exec -it --user $terminalUser `
  $terminalContainer `
  bash -lc 'DISPLAY=${DISPLAY:-:0} DONT_PROMPT_WSL_INSTALL=1 code --disable-gpu --no-sandbox --disable-dev-shm-usage --verbose'
```

So VS Code should be using:

- `HOME=/home/vscode-tester`
- Default extension path: `/home/vscode-tester/.vscode/extensions`

## Hypotheses / Open Questions

1. **VS Code CLI vs GUI mismatch**
   - When running CLI commands like `code --list-extensions`, earlier we observed crashes with `v8::ToLocalChecked Empty MaybeLocal` in this WSL+Podman environment. It is unclear whether the GUI is reading the same extension metadata or if a separate user data directory is being used that ignores the manually-unzipped extensions.

2. **VS Code user data vs extensions location**
   - It is possible that this specific tarball build expects extensions under a different path (for example, a variation of `~/.vscode-server/extensions` or a different product name), and that `~/.vscode/extensions` is not being scanned. We have not yet introspected the VS Code settings or logs inside the container to confirm.

3. **Product name / variant differences**
   - Some distributions (VS Code vs VSCodium vs OSS builds) use different extension roots. We are using the official `vscode-linux-x64` tarball; we need to confirm that it actually uses `~/.vscode/extensions` in this environment, and not a different vendor-specific directory.

4. **Permissions or metadata expectations**
   - Although directory ownership is set to `vscode-tester:vscode-tester` and unzipped content looks correct, there may be required metadata (such as a specific `package.json` location or extension ID folder naming) that the manual unzip approach is not satisfying.

## Next Steps for Investigation

Suggested follow-up for another developer:

1. Inside `vscode-terminal` as `vscode-tester`, inspect:

   ```bash
   echo "HOME=$HOME"
   echo "VSCODE_PORTABLE=$VSCODE_PORTABLE"
   env | grep -i vscode
   ```

2. Start VS Code with extended logging:

   ```bash
   DISPLAY=:0 DONT_PROMPT_WSL_INSTALL=1 \
     /home/vscode-tester/.local/vscode/bin/code --verbose 2>&1 | tee /tmp/code-verbose.log
   ```

   and look for:
   - Which extension directory paths it scans.
   - Any warnings about extension loading or corrupted extensions.

3. Try pointing `--extensions-dir` explicitly to `~/.vscode/extensions` and see if the extensions then appear:

   ```bash
   DISPLAY=:0 DONT_PROMPT_WSL_INSTALL=1 \
     /home/vscode-tester/.local/vscode/bin/code \
       --extensions-dir /home/vscode-tester/.vscode/extensions --verbose
   ```

4. Compare behavior with a clean VS Code install on a pure WSL Ubuntu (no Podman) to rule out WSLg-specific differences.

## Summary

- **On disk**: all desired extensions are present in `/home/vscode-tester/.vscode/extensions` inside the terminal container.
- **In the GUI (initially)**: VS Code did not list them as installed when launched via `launch-vscode-in-terminal-container.ps1`.
- Root cause was not initially identified; most likely candidates were:
  - VS Code using an unexpected extensions root in this environment.
  - Manual unzip install missing some metadata VS Code’s extension manager expects.

See “Resolution / Root Cause and Fix” below for the final diagnosis and fix.

## Resolution / Root Cause and Fix

### Root cause

During investigation inside a freshly built `vscode-terminal` container (as user `vscode-tester`), the following was observed:

- The manual install step in `simulate/terminal.Dockerfile` unzipped each `.vsix` into:

  - `~/.vscode/extensions/<vsix-basename>/`

- For the extensions fetched from Open VSX, the actual extension payload was nested under an additional `extension/` directory, for example:

  - `~/.vscode/extensions/eamodio.gitlens-latest/extension/package.json`

- VS Code’s extension scanner expects each extension folder under `~/.vscode/extensions` to have a `package.json` at the **folder root**, not under `extension/`. With `package.json` hidden one level deeper, VS Code ignored those directories.
- This explained the behavior:
  - `ls ~/.vscode/extensions` showed the expected folders.
  - `code --list-extensions` returned nothing for those folders.
  - Installing a `.vsix` via the CLI (`code --install-extension`) created a *different* folder (for example `eamodio.gitlens-2025.11.2404`) with `package.json` at the root, and that folder was detected correctly.

In short: the preinstalled extensions were in the right base directory but had the wrong internal layout (`extension/` nesting), so VS Code did not recognize them as installed.

### Fix in `terminal.Dockerfile`

The manual extension install loop in `install-vscode-offline/simulate/terminal.Dockerfile` was updated to **flatten** the `extension/` payload into the extension root after unzipping.

Updated snippet (core logic):

```dockerfile
ARG SSH_USERNAME
RUN set -eux; \
    EXT_DIR="/home/${SSH_USERNAME}/.vscode/extensions"; \
    mkdir -p "${EXT_DIR}"; \
    if ls /pkgs-extensions/*.vsix >/dev/null 2>&1; then \
        echo "==> Installing VS Code extensions from /pkgs-extensions (manual unzip)"; \
        EXTENSION_COUNT=$(ls /pkgs-extensions/*.vsix | wc -l); \
        echo "==> Found ${EXTENSION_COUNT} extension(s)"; \
        for VSIX in /pkgs-extensions/*.vsix; do \
            VSIX_BASENAME=$(basename "${VSIX}"); \
            EXT_NAME="${VSIX_BASENAME%.vsix}"; \
            TARGET_DIR="${EXT_DIR}/${EXT_NAME}"; \
            echo "==> Installing: ${VSIX_BASENAME} -> ${TARGET_DIR}"; \
            rm -rf "${TARGET_DIR}"; \
            mkdir -p "${TARGET_DIR}"; \
            unzip -q "${VSIX}" -d "${TARGET_DIR}"; \
            if [ -d "${TARGET_DIR}/extension" ]; then \
                echo "    -> Flattening 'extension/' payload into ${TARGET_DIR}"; \
                cp -a "${TARGET_DIR}/extension/." "${TARGET_DIR}/"; \
                rm -rf "${TARGET_DIR}/extension"; \
            fi; \
        done; \
        chown -R "${SSH_USERNAME}:${SSH_USERNAME}" "${EXT_DIR}"; \
        echo "==> Extensions installed under ${EXT_DIR}"; \
    else \
        echo "==> No .vsix extension files found in /pkgs-extensions"; \
        echo "==> VS Code will run without extensions"; \
    fi
```

This change preserves the existing folder naming (for example `eamodio.gitlens-latest`) but ensures each folder now contains a `package.json` and extension files at the top level, matching what `code --install-extension` would produce.

### Verification steps

After applying the Dockerfile change:

1. Rebuild the terminal image from the repo root:

   ```powershell
   cd C:\Users\<user>\systalk
   install-vscode-offline\simulate\build-terminal-docker.ps1 -NoCache
   ```

2. Restart the terminal + server containers:

   ```powershell
   cd C:\Users\<user>\systalk\install-vscode-offline\simulate
   .\start-both.ps1 -Yes
   ```

3. Inside the `vscode-terminal` container as `vscode-tester`, confirm:

   ```bash
   # inside container
   echo "HOME=$HOME"
   ls -1 ~/.vscode/extensions
   /home/vscode-tester/.local/vscode/bin/code --list-extensions
   ```

   Expected output:

   - `~/.vscode/extensions` contains:
     - `eamodio.gitlens-latest`
     - `ms-python.python-latest`
     - `ms-vscode-remote.remote-ssh-latest`
     - `saoudrizwan.claude-dev-openvsx`
     - `shd101wyy.markdown-preview-enhanced-openvsx`
   - `code --list-extensions` reports:
     - `eamodio.gitlens`
     - `ms-python.python`
     - `ms-vscode-remote.remote-ssh`
     - `saoudrizwan.claude-dev`
     - `shd101wyy.markdown-preview-enhanced`

4. Launch VS Code via:

   ```powershell
   cd C:\Users\<user>\systalk\install-vscode-offline\simulate
   .\launch-vscode-in-terminal-container.ps1
   ```

   The Extensions view in the VS Code GUI should now show the preinstalled extensions as installed, matching the CLI output above.
