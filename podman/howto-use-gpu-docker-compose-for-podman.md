# How to Use GPU with Docker Compose for Podman

This guide explains how to use NVIDIA GPUs with `docker-compose` when running on Podman. **The standard Docker Compose GPU syntax does not work with Podman** — you need to use Podman's CDI (Container Device Interface) approach.

## The Problem

Docker Compose typically uses this syntax for GPU access:

```yaml
# ❌ DOES NOT WORK with Podman
services:
  app:
    image: nvidia/cuda:12.0-base
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
```

This syntax is Docker-specific and **will not work with Podman**. Similarly, the `--gpus` flag is a no-op in Podman (exists only for Docker CLI compatibility).

## Prerequisites

Before using GPU in compose files, ensure:

1. **NVIDIA driver** is installed on your Windows host
2. **Podman machine** is initialized and running
3. **NVIDIA Container Toolkit** is installed inside the Podman machine
4. **CDI specification** is generated

If you haven't set up NVIDIA runtime yet, run:
```powershell
.\install-nvidia-runtime.ps1
```

Or manually install inside the Podman machine:
```bash
# SSH into the Podman machine
podman machine ssh

# Install NVIDIA Container Toolkit (Fedora-based machine)
curl -s -L https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo | sudo tee /etc/yum.repos.d/nvidia-container-toolkit.repo
sudo yum install -y nvidia-container-toolkit

# Generate CDI specification
sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml

# Verify GPU is detected
nvidia-ctk cdi list
```

Expected output:
```
INFO[0000] Found 1 CDI devices
nvidia.com/gpu=0
nvidia.com/gpu=all
```

## Working Compose Configurations

### Method 1: Direct Device Mapping (Recommended)

The simplest and most reliable method. Use `devices` with CDI device names:

```yaml
services:
  cuda-app:
    image: nvidia/cuda:12.0-base
    devices:
      - nvidia.com/gpu=all
    security_opt:
      - label=disable
    command: nvidia-smi
```

To use specific GPUs:
```yaml
services:
  cuda-app:
    image: nvidia/cuda:12.0-base
    devices:
      - nvidia.com/gpu=0      # First GPU only
      # - nvidia.com/gpu=1    # Second GPU (if available)
    security_opt:
      - label=disable
```

### Method 2: CDI Driver Syntax (Podman 5.4.0+)

For Podman v5.4.0 and later, the CDI driver syntax in deploy resources works:

```yaml
services:
  cuda-app:
    image: nvidia/cuda:12.0-base
    deploy:
      resources:
        reservations:
          devices:
            - driver: cdi
              device_ids:
                - nvidia.com/gpu=all
    security_opt:
      - label=disable
    command: nvidia-smi
```

### Method 3: Runtime with Environment Variable

This method uses the NVIDIA runtime with environment variable:

```yaml
services:
  cuda-app:
    image: nvidia/cuda:12.0-base
    runtime: nvidia
    environment:
      - NVIDIA_VISIBLE_DEVICES=all
    security_opt:
      - label=disable
    command: nvidia-smi
```

> **Note:** This method requires the NVIDIA Container Runtime hook to be installed, which may conflict with CDI. Method 1 is preferred.

## Complete Example: Ollama with GPU

```yaml
version: "3.8"

services:
  ollama:
    image: ollama/ollama:latest
    container_name: ollama
    devices:
      - nvidia.com/gpu=all
    security_opt:
      - label=disable
    ports:
      - "11434:11434"
    volumes:
      - ollama_data:/root/.ollama
    restart: unless-stopped

volumes:
  ollama_data:
```

Run with:
```powershell
docker-compose up -d
```

Verify GPU access:
```powershell
docker-compose exec ollama nvidia-smi
```

## Complete Example: PyTorch Development

```yaml
version: "3.8"

services:
  pytorch:
    image: pytorch/pytorch:2.1.0-cuda12.1-cudnn8-runtime
    container_name: pytorch-dev
    devices:
      - nvidia.com/gpu=all
    security_opt:
      - label=disable
    volumes:
      - ./src:/workspace
    working_dir: /workspace
    stdin_open: true
    tty: true
    command: bash

  jupyter:
    image: pytorch/pytorch:2.1.0-cuda12.1-cudnn8-runtime
    container_name: pytorch-jupyter
    devices:
      - nvidia.com/gpu=all
    security_opt:
      - label=disable
    ports:
      - "8888:8888"
    volumes:
      - ./notebooks:/workspace
    working_dir: /workspace
    command: >
      bash -c "pip install jupyter &&
               jupyter notebook --ip=0.0.0.0 --port=8888 --no-browser --allow-root"
```

## Comparison: Docker vs Podman GPU Syntax

| Feature | Docker Compose | Podman Compose |
|---------|---------------|----------------|
| Device driver | `driver: nvidia` | `driver: cdi` or direct `devices:` |
| GPU specification | `count: all` or `count: 1` | `nvidia.com/gpu=all` or `nvidia.com/gpu=0` |
| Capabilities | `capabilities: [gpu]` | Not needed (CDI handles this) |
| Runtime | `runtime: nvidia` | Optional, prefer CDI devices |
| `--gpus` flag | Works | No-op (ignored) |

## Troubleshooting

### GPU not detected in container

1. **Verify CDI is generated:**
   ```bash
   podman machine ssh -- nvidia-ctk cdi list
   ```

   If empty, regenerate:
   ```bash
   podman machine ssh -- sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml
   ```

2. **Restart Podman machine after installing NVIDIA toolkit:**
   ```powershell
   podman machine stop
   podman machine start
   ```

3. **Check your Podman version:**
   ```powershell
   podman --version
   ```
   Ensure you're on v5.0.0+ for best CDI support, v5.4.0+ for CDI driver in compose.

### "unresolvable CDI devices" error

The CDI specification may reference an old NVIDIA driver version. Regenerate it:
```bash
podman machine ssh -- sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml
```

### SELinux blocks GPU access

Add `security_opt: [label=disable]` to your service, or run:
```bash
podman machine ssh -- sudo setsebool -P container_use_devices 1
```

### Compose file works with `podman-compose` but not `docker-compose`

This is a known compatibility issue. Try:
1. Update to latest Podman (v5.4.0+)
2. Use Method 1 (direct device mapping) which has best compatibility
3. Use `podman-compose` instead of `docker-compose` as a workaround

### Container starts but CUDA reports no GPU

Check if the container can see the GPU:
```bash
docker-compose exec <service> ls -la /dev/nvidia*
docker-compose exec <service> nvidia-smi
```

If devices exist but CUDA fails, ensure your image is compatible with your driver version.

## Quick Reference

**Minimal compose.yaml for GPU:**
```yaml
services:
  gpu-app:
    image: nvidia/cuda:12.0-base
    devices:
      - nvidia.com/gpu=all
    security_opt:
      - label=disable
```

**Test GPU access:**
```powershell
# Direct podman (should always work)
podman run --rm --device nvidia.com/gpu=all nvidia/cuda:12.0-base nvidia-smi

# Via compose
docker-compose run --rm gpu-app nvidia-smi
```

## References

- [Podman Desktop GPU Documentation](https://podman-desktop.io/docs/podman/gpu)
- [NVIDIA Container Toolkit CDI Support](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/cdi-support.html)
- [GitHub Issue: CDI driver in docker-compose](https://github.com/containers/podman/issues/19338)
- [GitHub Issue: GPU in podman compose vs podman run](https://github.com/containers/podman/issues/25196)
- [NVIDIA Developer Forums: Podman Compose GPU Support](https://forums.developer.nvidia.com/t/podman-compose-not-working-with-gpu-support/292349)
