Here’s the clean, supported way to run **Docker on Windows 11 without Docker Desktop**: install Docker Engine *inside WSL 2 (Ubuntu)* and use it from that Linux shell (or optionally from Windows via a TCP socket).

# 1) Install WSL 2 + Ubuntu

Open **PowerShell (Admin)** and run:

```powershell
wsl --install -d Ubuntu
wsl --set-default-version 2
```

Then launch “Ubuntu” from Start to finish the first-run setup. ([Microsoft Learn][1])

# 2) Enable systemd in WSL (so `dockerd` runs as a service)

Inside Ubuntu:

```bash


sudo nano /etc/wsl.conf
```

Add:

```
[boot]
systemd=true
```

Back in PowerShell:

```powershell
wsl --shutdown
```

Reopen Ubuntu and check:

```bash
systemctl status
```

You should see systemd active. ([Microsoft Learn][2])

# 3) Install Docker Engine (CE) in Ubuntu

Still inside Ubuntu:

```bash
# 3.1 prerequisites + Docker APT repo
sudo apt-get update
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
  https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update

# 3.2 install engine + CLI + compose v2
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

Docker starts automatically; verify:

```bash
sudo systemctl status docker
sudo docker run hello-world
```

(If needed: `sudo systemctl start docker`.) ([Docker Documentation][3])

**Note:** If you need GPU/CUDA support for machine learning or scientific computing, see the **NVIDIA GPU Support** section below.

# 4) Let your normal user run `docker` (no `sudo`)

```bash
sudo groupadd docker 2>/dev/null || true
sudo usermod -aG docker $USER
newgrp docker
docker run hello-world
```

(Adding yourself to the `docker` group grants root-equivalent access to the daemon—understand the security trade-off.) ([Docker Documentation][4])

# 5) Make Docker start automatically in WSL

```bash
sudo systemctl enable docker.service
sudo systemctl enable containerd.service
```

([Docker Documentation][4])

---

## (Optional) Use the Windows **docker.exe** CLI without Desktop

The simplest workflow is to run `docker …` **inside the Ubuntu (WSL) shell**. If you prefer using PowerShell/CMD, expose the Linux daemon on localhost and point the Windows CLI at it:

**In Ubuntu (WSL):**

```bash
# bind dockerd to unix socket + localhost:2375 (no TLS)
echo '{"hosts":["unix:///var/run/docker.sock","tcp://127.0.0.1:2375"]}' | \
  sudo tee /etc/docker/daemon.json
sudo systemctl restart docker
```

**In Windows (PowerShell):**

```powershell
$env:DOCKER_HOST="tcp://127.0.0.1:2375"
docker version
```

⚠️ Opening the Docker API over TCP **without TLS is insecure**; keep it bound to `127.0.0.1` only, or configure proper TLS as per the docs. ([Docker Documentation][5])

---

## Good to know (WSL + Docker tips)

* **Keep project files inside the Linux filesystem** (e.g., `~/src`) and bind-mount from there; accessing `/mnt/c/...` is noticeably slower for dev workloads. ([Docker][6])
* This setup runs **Linux containers**. Running *Windows containers* without Docker Desktop requires different runtimes (Moby/Mirantis/containerd) and targets Windows **Server** scenarios. ([Microsoft Learn][7])

---

## (Optional) NVIDIA GPU Support for Docker on WSL2

If you need CUDA/GPU support in Docker containers (machine learning, scientific computing, etc.), follow these steps to install the **NVIDIA Container Toolkit**.

### Prerequisites for GPU Support

* **Hardware**: NVIDIA GPU with Pascal architecture or later (GTX 10-series, RTX series, Quadro, etc.)
  * Maxwell GPUs are **NOT supported**
* **Windows Version**: Windows 11 (any build) or Windows 10 with Windows Insider Program
* **WSL2**: Kernel version 4.19.121+ (5.10.16.3+ recommended)
  * Update with: `wsl.exe --update` (in PowerShell)

⚠️ **CRITICAL**: Do **NOT** install any NVIDIA Linux driver inside WSL2. The Windows driver is automatically exposed to WSL2.

### Step 1: Install NVIDIA Windows Driver

**In Windows (not WSL):**

1. Download and install the latest **NVIDIA GeForce Game Ready** or **NVIDIA RTX Quadro** driver:
   * Visit: https://www.nvidia.com/download/index.aspx
   * Minimum version: R495 (R510+ recommended)
   * This is the **only** driver you need

2. Verify the driver is working (in Windows):
   * Open NVIDIA Control Panel or run: `nvidia-smi` in PowerShell

### Step 2: Verify GPU is Accessible in WSL2

**In Ubuntu (WSL):**

```bash
# This should show your GPU information
# If command not found, the Windows driver exposes the GPU but nvidia-smi isn't installed yet
nvidia-smi
```

If `nvidia-smi` is not found but you have the Windows driver installed, that's expected—we'll get the toolkit next.

### Step 3: Install NVIDIA Container Toolkit in Ubuntu

**In Ubuntu (WSL):**

```bash
# 3.1 Install prerequisites
sudo apt-get update
sudo apt-get install -y curl gnupg2

# 3.2 Configure NVIDIA Container Toolkit repository
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
  sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
  sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

# 3.3 Update package list
sudo apt-get update

# 3.4 Install NVIDIA Container Toolkit
sudo apt-get install -y nvidia-container-toolkit

# 3.5 Configure Docker to use NVIDIA runtime
sudo nvidia-ctk runtime configure --runtime=docker

# 3.6 Restart Docker to apply changes
sudo systemctl restart docker
```

### Step 4: Verify GPU Support in Docker

**Test that Docker can access your GPU:**

```bash
# Run a CUDA container and check GPU access
docker run --rm --gpus all nvidia/cuda:12.4.0-base-ubuntu22.04 nvidia-smi
```

You should see output showing:
* Your GPU model (e.g., RTX 4090, GTX 1080 Ti, etc.)
* Driver version
* CUDA version
* GPU memory information

**Alternative test with a simple CUDA sample:**

```bash
# Run deviceQuery sample
docker run --rm --gpus all nvidia/cuda:12.4.0-devel-ubuntu22.04 \
  bash -c 'apt-get update && apt-get install -y cuda-samples-12-4 && \
  cd /usr/local/cuda/samples/1_Utilities/deviceQuery && \
  make && ./deviceQuery'
```

Expected output should end with: `Result = PASS`

### Troubleshooting GPU Support

**Problem: "could not select device driver with capabilities: [[gpu]]"**
```bash
# Solution: Reconfigure Docker runtime and restart
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
```

**Problem: "Failed to initialize NVML: Unknown Error"**
```bash
# Check if WSL can see the GPU at the system level
ls -la /dev/dxg   # Should exist
ls -la /usr/lib/wsl/lib/  # Should contain libcuda.so, libnvidia-ml.so

# If missing, update WSL kernel:
# (In PowerShell as Admin)
wsl.exe --update
wsl.exe --shutdown
# Then restart Ubuntu
```

**Problem: `nvidia-smi` shows "No devices were found"**
* Verify Windows NVIDIA driver is installed (check Windows Device Manager)
* Update WSL2 kernel: `wsl.exe --update` (in PowerShell)
* Ensure GPU is not disabled in BIOS/UEFI

### Installing CUDA Toolkit (Optional)

If you need to compile CUDA code **inside WSL** (not in containers):

```bash
# Install WSL-specific CUDA Toolkit (NO DRIVER)
wget https://developer.download.nvidia.com/compute/cuda/repos/wsl-ubuntu/x86_64/cuda-keyring_1.1-1_all.deb
sudo dpkg -i cuda-keyring_1.1-1_all.deb
sudo apt-get update
sudo apt-get install -y cuda-toolkit-12-4  # Or latest version

# Add to PATH (add to ~/.bashrc for persistence)
export PATH=/usr/local/cuda/bin:$PATH
export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH
```

⚠️ Use `cuda-toolkit-*` packages, **NOT** `cuda` or `cuda-drivers` meta-packages (those try to install drivers).

### Running GPU-Accelerated Containers

Examples of using GPU in containers:

```bash
# PyTorch with GPU
docker run --rm --gpus all -it pytorch/pytorch:latest python -c \
  "import torch; print(f'CUDA available: {torch.cuda.is_available()}'); print(f'GPU: {torch.cuda.get_device_name(0) if torch.cuda.is_available() else \"N/A\"}')"

# TensorFlow with GPU
docker run --rm --gpus all -it tensorflow/tensorflow:latest-gpu python -c \
  "import tensorflow as tf; print(f'GPU devices: {tf.config.list_physical_devices(\"GPU\")}')"

# Limit to specific GPU (if you have multiple)
docker run --rm --gpus '"device=0"' nvidia/cuda:12.4.0-base-ubuntu22.04 nvidia-smi

# Allocate only 2 GPUs
docker run --rm --gpus 2 nvidia/cuda:12.4.0-base-ubuntu22.04 nvidia-smi

# Allocate GPUs with specific capabilities
docker run --rm --gpus '"capabilities=compute,utility"' nvidia/cuda:12.4.0-base-ubuntu22.04 nvidia-smi
```

### Docker Compose with GPU Support

Example `docker-compose.yml`:

```yaml
version: '3.8'

services:
  ml-app:
    image: pytorch/pytorch:latest
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all  # or: count: 1, or: device_ids: ['0', '1']
              capabilities: [gpu]
    command: python train.py
```

---

### Sources

#### Docker & WSL Setup
* Microsoft: **Install WSL** and **enable systemd in WSL**. ([Microsoft Learn][1], [Microsoft Learn][2])
* Docker: **Install Docker Engine on Ubuntu**, **Linux post-install**, **remote access to daemon**. ([Docker Documentation][3], [Docker Documentation][4], [Docker Documentation][5])
* Docker blog: **WSL 2 best practices** (store code in Linux FS, run CLI in WSL). ([Docker][6])

#### NVIDIA GPU Support
* NVIDIA: **Container Toolkit Installation Guide** (official installation instructions). ([NVIDIA Docs][8])
* NVIDIA: **CUDA on WSL User Guide** (WSL-specific requirements and driver info). ([NVIDIA Docs][9])
* NVIDIA: **NVIDIA Container Toolkit Documentation** (runtime configuration and usage). ([NVIDIA Docs][10])

#### Additional Resources
* Microsoft: **Windows Containers** (for native Windows container scenarios). ([Microsoft Learn][7])

---

**Notes:**
* This guide is tested on **Windows 11** with **Ubuntu 24.04** in WSL2
* For TLS setup with Windows Docker CLI or other customizations, consult the official Docker daemon remote access documentation
* Keep WSL2 kernel updated regularly: `wsl.exe --update` (in PowerShell)

---

[1]: https://learn.microsoft.com/en-us/windows/wsl/install "Install WSL | Microsoft Learn"
[2]: https://learn.microsoft.com/en-us/windows/wsl/systemd "Use systemd to manage Linux services with WSL | Microsoft Learn"
[3]: https://docs.docker.com/engine/install/ubuntu/ "Install Docker Engine on Ubuntu | Docker Docs"
[4]: https://docs.docker.com/engine/install/linux-postinstall/ "Post-installation steps for Linux | Docker Docs"
[5]: https://docs.docker.com/engine/daemon/remote-access/ "Configure remote access for Docker daemon | Docker Docs"
[6]: https://www.docker.com/blog/docker-desktop-wsl-2-best-practices/ "Docker Desktop: WSL 2 Best practices"
[7]: https://learn.microsoft.com/en-us/virtualization/windowscontainers/quick-start/set-up-environment "Prepare Windows operating system containers | Microsoft Learn"
[8]: https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html "Installing the NVIDIA Container Toolkit | NVIDIA Docs"
[9]: https://docs.nvidia.com/cuda/wsl-user-guide/index.html "CUDA on WSL User Guide | NVIDIA Docs"
[10]: https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/ "NVIDIA Container Toolkit Documentation | NVIDIA Docs"
