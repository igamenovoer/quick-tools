# Simulate Air-Gapped VS Code Remote-SSH with Two Docker Containers (Ubuntu 24.04)

This document describes how to **simulate an air-gapped remote dev setup** using **two Docker containers**:

- **Container A (terminal machine)** – runs a full VS Code GUI, displayed on the host using X11 forwarding.
- **Container B (GPU server)** – runs an SSH-accessible Linux environment with the VS Code server (“code server” component) pre-installed from an offline package.

VS Code in container A connects to container B over SSH using the Remote-SSH extension. Container B has **no internet access** during normal operation, so we can verify that remote development works entirely from pre-downloaded bits.

This plan still uses:

- `download-latest-vscode-package.ps1` – download VS Code, VS Code Server, and Remote-SSH extensions.
- `install-remote.ps1` – install VS Code Server on a remote Linux host from the offline package.
- A local package cache in `install-vscode-offline/simulate/pkgs` – all `.deb` files downloaded once and then reused for offline Docker builds.

---

## 0. Prerequisites and Topology

- Host OS: Windows 10/11 or Linux with:
  - Docker installed and working (`docker --version`).
  - An X11 server running on the host to display VS Code from container A (for example, XQuartz/VcXsrv on Windows, native Xorg on Linux).
- Repo cloned at something like: `C:\Users\igamenovoer\systalk\install-vscode-offline` (Windows) or the equivalent path on Linux.
- A directory `install-vscode-offline/simulate/pkgs` containing all required Ubuntu `.deb` packages for:
  - `openssh-server`, `sudo`, `tar`, `curl`, `ca-certificates`, and any other tools you need.
  - All their dependencies for Ubuntu 24.04 (noble).

These `.deb` files are downloaded from the internet **once** (on any machine with access) and then copied into `simulate/pkgs`. Building the Docker images and running containers can be done **fully offline** afterwards.

Simulation topology:

- **Host** (online only during preparation):
  - Runs Docker and the X11 server.
  - Runs `download-latest-vscode-package.ps1`.
  - Optionally runs `install-remote.ps1` to preload VS Code Server into container B.
- **Container A (terminal VS Code)**:
  - Based on Ubuntu 24.04, with VS Code GUI and Remote-SSH extension installed from the offline package.
  - Has SSH client and X11 libraries; connects back to host X11 display.
- **Container B (offline GPU server)**:
  - Based on Ubuntu 24.04, built from `simulate/server.Dockerfile` with SSH and base tools.
  - VS Code Server installed from the offline package.
  - Connected to container A on an internal Docker network, with no internet access.

---

## 1. Build Container B (Offline GPU Server, Using Local `pkgs/` Only)

Goal: Build a Docker image for container B in `simulate/` that contains Ubuntu 24.04, SSH, and all required tools, **installed only from `.deb` files in `simulate/pkgs`**. Once containers are created from this image, we will treat container B as air-gapped and will not run `apt` inside it.

1. Ensure `simulate/pkgs` is populated with all required `.deb` files for Ubuntu 24.04 (noble):

   - Required for VS Code Server per official docs:
     - `libc6`, `libstdc++6`, `ca-certificates`, `tar`.
     - `openssh-server`, `bash`, and `curl` (or `wget`).
   - Plus any extra tools you want (`sudo`, `git`, etc.).

   You can obtain these packages on an online machine using `apt-get download` or similar and then copy them into `simulate/pkgs`. Once this directory is complete, no more internet is needed for the Docker build.

2. Use `simulate/server.Dockerfile` to build the base image:

   ```powershell
   cd C:\Users\igamenovoer\systalk\install-vscode-offline\simulate
   docker build -f server.Dockerfile -t vscode-airgap-server:latest .
   ```

3. Create an **internal Docker network** so containers can talk to each other but not the internet:

   ```bash
   docker network create --internal vscode-airgap-net
   ```

4. Start container B from this image and **treat it as air-gapped**:

   ```bash
  docker run -d \
    --name vscode-remote \
    --network vscode-airgap-net \
    vscode-airgap-server:latest
   ```

5. Verify SSH works by temporarily publishing the SSH port to the host (for example, while running `install-remote.ps1`), or by attaching from container A once it exists. After validation, keep container B on the internal network only.

---

## 2. Download VS Code Offline Package (Online Phase)

Goal: Download **all VS Code components** needed later in the air-gapped environment. This phase is identical to the original workflow, but the package will be consumed by both container A (VS Code GUI) and container B (VS Code Server).

1. On the host, go to the main offline scripts directory:

   ```powershell
   cd C:\Users\igamenovoer\systalk\install-vscode-offline
   ```

2. Download the latest VS Code package to a dedicated folder, for example `.\vscode-package`:

   ```powershell
   .\download-latest-vscode-package.ps1 -Output ".\vscode-package"
   ```

   This will create a directory like:

   ```text
   vscode-package\
     VSCodeUserSetup-x64-<version>.exe
     ms-vscode-remote.remote-ssh-latest.vsix
     ms-vscode-remote.remote-ssh-edit-latest.vsix
     vscode-server-linux-x64-<commit>.tar.gz
     vscode-server-linux-arm64-<commit>.tar.gz
     package-info.json
     README.txt
   ```

3. (Optional) Pin a specific VS Code version if you want reproducibility:

   ```powershell
   .\download-latest-vscode-package.ps1 `
       -Output ".\vscode-package" `
       -Version "1.105.1"
   ```

This offline package is the single source of truth for VS Code, Remote-SSH, and the VS Code server binaries used in both containers.

---

## 3. Build Container A (Terminal Machine with VS Code GUI)

Goal: Build a Docker image for container A that can run VS Code with GUI and Remote-SSH extension, using only the offline package and local `.deb` cache as inputs.

High-level requirements for the **terminal image** (implemented in `simulate/terminal.Dockerfile`):

- Base: `ubuntu:24.04` (or similar) with X11 libraries and fonts installed from `simulate/pkgs`.
- Install:
  - VS Code desktop from the offline installer or Linux tarball (copied in at build time).
  - Remote-SSH and other required extensions from `.vsix` files in `vscode-package`.
  - SSH client and convenience tools (`openssh-client`, `bash`, `curl`, etc.) from `simulate/pkgs`.
- Configure the container to:
  - Respect `DISPLAY` and `XAUTHORITY` so VS Code can render to the host X11 server.
  - Use a non-root user (for example, `devuser`) with a home directory where VS Code settings and extensions live.

Example run command (Linux host with X11):

```bash
docker run -it \
  --name vscode-terminal \
  --network vscode-airgap-net \
  -e DISPLAY=$DISPLAY \
  -v /tmp/.X11-unix:/tmp/.X11-unix:ro \
  vscode-airgap-terminal:latest \
  bash
```

Inside this shell, you can start VS Code (for example, `code`) and the GUI will appear on the host thanks to X11 forwarding.

On Windows, use an X11 server such as VcXsrv and set `DISPLAY` appropriately (for example, `-e DISPLAY=host.docker.internal:0.0`).

---

## 4. Install VS Code Server into Container B (Offline)

Goal: Use the offline package to install **VS Code Server** into container B over SSH, without container B accessing the internet.

You can reuse `install-remote.ps1` exactly as before, with container B acting as the remote host:

1. From the host (or from within container A, if you mount the repo), run `install-remote.ps1` pointing at container B. For example, if you temporarily publish B’s SSH port on the host:

   ```powershell
   cd C:\Users\igamenovoer\systalk\install-vscode-offline

   # Example: container B SSH exposed on host port 4444
   .\install-remote.ps1 `
       -OfflinePackageDir ".\vscode-package" `
       -SshHost "admin@localhost" `
       -SshPort 4444 `
       -SshPassword "admin"
   ```

2. After installation, you can move container B back to the internal network only. The VS Code Server bits are now present under:

   ```bash
   ~/.vscode-server/cli/servers/Stable-<commit>/server/
   ```

3. Optionally, verify from inside container B:

   ```bash
   docker exec -it vscode-remote bash
   ls -R /home/admin/.vscode-server/cli/servers
   ```

At this point, container B has the exact VS Code Server bits that VS Code expects, pre-loaded without any live downloads.

---

## 5. Connect from Container A’s VS Code via Remote-SSH (Fully Offline)

Goal: Prove that VS Code running inside container A can open a Remote-SSH session to container B **without container B downloading anything**.

1. Ensure both containers are running on the internal network `vscode-airgap-net`:

   ```bash
   docker ps
   # You should see vscode-terminal and vscode-remote
   ```

2. Attach to container A and start VS Code:

   ```bash
   docker exec -it vscode-terminal bash
   code
   ```

   The VS Code GUI should appear on the host via X11.

3. Inside VS Code (container A), ensure the **Remote-SSH** extension is enabled (installed from `.vsix` during build).

4. Add an SSH configuration or just connect directly to container B on the internal network, for example using the container name:

   - Press `F1` → type `Remote-SSH: Connect to Host...`.
   - Enter:

     ```text
     ssh admin@vscode-remote
     ```

   - When prompted for the platform, choose **Linux**.
   - Use password `admin` if prompted.

5. VS Code should attach to the already-installed VS Code Server in container B:

   - You should see the green remote indicator: `SSH: admin@vscode-remote`.
   - Open a folder inside container B (for example `/home/admin`).
   - Open a terminal in VS Code and confirm it runs in container B.

6. Confirm that container B is **truly offline**:

   - Inside the VS Code terminal (remote session in B), run:

     ```bash
     ping -c 3 8.8.8.8      # should fail if no outbound internet
     curl https://example.com || echo "no internet"
     ```

   - VS Code remains fully functional because the server bits and extensions were pre-installed from the offline package.

---

## 6. Mapping to a Real Air-Gapped Deployment

Once this two-container Docker simulation works end-to-end, the real setup is almost the same, just replacing containers with physical machines:

- **Online staging host**:
  - Run `download-latest-vscode-package.ps1`.
  - Optionally build and test updated terminal/remote images.
  - Copy resulting package to removable media.

- **Offline terminal machine (CPU server / admin jump box)**:
  - Install VS Code from the offline installer.
  - Install Remote-SSH extensions from `.vsix`.
  - Optionally run `install-remote.ps1` to stage VS Code Server onto the real GPU server.

- **Offline GPU server**:
  - Must have SSH, `tar`, and sufficient disk space.
  - Receives VS Code Server tarball via `install-remote.ps1` (or manually).
  - No direct internet access required.

This two-container layout is a repeatable, low-risk way to validate an offline Remote-SSH workflow where the "terminal machine" and "GPU server" are both simulated, but the behavior matches a real air-gapped deployment.

---

## 7. Using Podman Compose (Alternative Workflow)

For a simpler orchestration experience, you can use `deprecated/podman-compose-both.yaml` to manage both containers together (legacy workflow).

### Prerequisites for WSLg GUI Support

When running VS Code GUI from a Podman container via WSLg on Windows:

- **Shared Memory**: Chromium (Electron/VS Code) requires increased shared memory (default 64MB is insufficient)
- **Sandbox Flags**: Container namespace isolation conflicts with Chromium's sandbox
- **Display Configuration**: X11 socket must be mounted from WSLg

The `deprecated/podman-compose-both.yaml` file includes all necessary configurations:
- `shm_size: '2gb'` for increased shared memory
- X11 socket mount from `/mnt/wslg/.X11-unix`
- Proper `DISPLAY` environment variable

### Quick Start with Podman Compose

1. **Build both images** (one-time setup):

   ```powershell
   cd C:\Users\igamenovoer\systalk\install-vscode-offline\simulate
   podman build -f terminal.Dockerfile -t localhost/vscode-airgap-terminal:latest .
   podman build -f server.Dockerfile -t localhost/vscode-airgap-server:latest .
   ```

2. **Start both containers**:

   ```powershell
   podman-compose -f deprecated/podman-compose-both.yaml up -d
   ```

3. **Launch VS Code GUI** (using the helper script):

   ```powershell
   .\deprecated\launch-vscode-compose.ps1
   ```

   Or manually:

   ```powershell
   podman exec -it vscode-terminal bash -c "code --disable-gpu --no-sandbox --disable-dev-shm-usage"
   ```

4. **Connect to the remote server** via Remote-SSH in VS Code:
   - Press `F1` → `Remote-SSH: Connect to Host...`
   - Enter: `vscode-tester@vscode-remote`
   - Password: `123456`
   - The SSH key is already configured for passwordless auth

5. **Stop the stack** when done:

   ```powershell
   podman-compose -f deprecated/podman-compose-both.yaml down
   ```

### Why the Extra Flags?

VS Code is built on Electron (Chromium), which has specific requirements in containerized environments:

- `--no-sandbox`: Disables Chromium's sandbox (safe since Podman provides container isolation)
- `--disable-dev-shm-usage`: Forces temp files to `/tmp` instead of `/dev/shm`
- `--disable-gpu`: Avoids GPU acceleration issues in X11 forwarding

See `install-vscode-offline/issues/issue-podman-vscode-gui.md` for the full technical explanation and troubleshooting steps.
