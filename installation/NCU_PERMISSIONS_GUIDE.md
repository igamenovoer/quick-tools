# NVIDIA Nsight Compute (ncu) Permission Setup Guide

## Problem Overview

When trying to use NVIDIA Nsight Compute (`ncu`) for GPU profiling, you may encounter the error:

```
ERR_NVGPUCTRPERM: The user does not have permission to access NVIDIA GPU Performance Counters on the target device.
```

This occurs because:
- NVIDIA drivers version **418.43+** (Linux) or **419.17+** (Windows) restrict GPU Performance Counter access
- This restriction was implemented for security reasons (see [NVIDIA Security Notice](https://nvidia.custhelp.com/app/answers/detail/a_id/4738))
- By default, only users with admin privileges can access GPU performance counters

## Quick Setup (Recommended)

Use the automated setup script:

```bash
# Make changes permanent (requires reboot)
sudo ./setup-ncu-permissions.sh

# Apply temporarily (until reboot, no reboot required)
sudo ./setup-ncu-permissions.sh --temporary
```

## Manual Setup

### Method 1: Permanent Configuration (Recommended)

This method persists across reboots.

**Step 1: Create modprobe configuration file**

Create `/etc/modprobe.d/nvidia-performance-counters.conf`:

```bash
sudo tee /etc/modprobe.d/nvidia-performance-counters.conf > /dev/null << 'EOF'
# Enable performance counter access for all users
options nvidia NVreg_RestrictProfilingToAdminUsers=0
options nvidia_drm NVreg_RestrictProfilingToAdminUsers=0
options nvidia_modeset NVreg_RestrictProfilingToAdminUsers=0
options nvidia_uvm NVreg_RestrictProfilingToAdminUsers=0
EOF
```

**Step 2: Rebuild initramfs**

For Debian/Ubuntu systems:
```bash
sudo update-initramfs -u -k all
```

For RedHat/CentOS/Fedora systems:
```bash
sudo dracut --regenerate-all -f
```

**Step 3: Reboot**
```bash
sudo reboot
```

### Method 2: Temporary Configuration

This method applies immediately but is lost after reboot.

**Step 1: Stop display manager and unload NVIDIA modules**

```bash
# Stop the display manager (this will close your GUI)
sudo systemctl isolate multi-user.target

# Check if any processes are using NVIDIA devices
sudo lsof /dev/nvidia*

# If processes are using the GPU, close them first, then unload modules
sudo modprobe -rf nvidia_uvm nvidia_drm nvidia_modeset nvidia-vgpu-vfio nvidia
```

**Step 2: Load modules with permission enabled**

```bash
sudo modprobe nvidia NVreg_RestrictProfilingToAdminUsers=0
```

**Step 3: Restart display manager (if needed)**

```bash
sudo systemctl isolate graphical.target
```

### Method 3: Run with Elevated Privileges (Quick Test)

For quick testing without system configuration:

```bash
# Run ncu with sudo
sudo ncu ./your_cuda_application

# Or run your application with CAP_SYS_ADMIN capability
sudo setcap cap_sys_admin+ep /path/to/your/application
./your_cuda_application
```

**Note:** This method requires sudo every time and is not recommended for regular use.

## Verification

Check if the configuration is applied:

```bash
# Check current kernel parameter
cat /proc/driver/nvidia/params | grep RmProfilingAdminOnly

# Should show: RmProfilingAdminOnly: 0
# 0 = all users can access performance counters
# 1 = only admin users can access
```

Test with ncu:

```bash
# Query available metrics (doesn't require a CUDA application)
ncu --query-metrics

# Profile a simple CUDA application
ncu ./your_cuda_app

# Profile with specific metrics
ncu --metrics sm__cycles_elapsed.avg ./your_cuda_app
```

## Docker Containers

If running ncu inside a Docker container:

**Option 1: Enable on host (recommended)**
```bash
# Apply the permanent configuration on the host system
sudo ./setup-ncu-permissions.sh
sudo reboot
```

**Option 2: Run container with elevated privileges**
```bash
docker run --gpus all --cap-add=SYS_ADMIN your_container
```

## Troubleshooting

### Problem: Changes don't take effect after reboot

**Solution 1:** Verify initramfs includes the configuration

For Debian/Ubuntu:
```bash
sudo lsinitramfs /boot/initrd.img | grep nvidia-performance-counters.conf
```

For RedHat/CentOS/Fedora:
```bash
sudo lsinitrd | grep nvidia-performance-counters.conf
```

**Solution 2:** Manually rebuild initramfs and reboot again

### Problem: Can't unload NVIDIA modules (temporary method)

**Cause:** Processes are still using the GPU

**Solution:** Find and close GPU processes
```bash
# List processes using NVIDIA devices
sudo lsof /dev/nvidia*

# Kill specific process
sudo kill <PID>

# Or force unload (may crash applications)
sudo rmmod nvidia_uvm nvidia_drm nvidia_modeset nvidia
```

### Problem: Still getting ERR_NVGPUCTRPERM after configuration

**Possible causes:**
1. System not rebooted (for permanent method)
2. Configuration file has wrong syntax
3. NVIDIA driver too old (< 418.43)

**Solutions:**
```bash
# 1. Verify driver version (should be 418.43+)
nvidia-smi

# 2. Check configuration file syntax
cat /etc/modprobe.d/nvidia-performance-counters.conf

# 3. Verify current setting
cat /proc/driver/nvidia/params | grep RmProfilingAdminOnly

# 4. Try running with sudo as a test
sudo ncu ./your_app
```

### Problem: Ubuntu package-managed driver (nvidia-xxx)

Ubuntu may rename the kernel module from `nvidia` to `nvidia-xxx` (e.g., `nvidia-525`).

**Solution:** Check module name and adjust:
```bash
# Check loaded modules
lsmod | grep nvidia

# If using nvidia-525, for example, modify modprobe command:
sudo modprobe nvidia-525 NVreg_RestrictProfilingToAdminUsers=0
```

## Security Considerations

⚠️ **Warning:** Enabling performance counter access for all users has security implications:

- GPU performance counters can potentially leak information about other processes
- This could be exploited for side-channel attacks
- See [NVIDIA Security Notice](https://nvidia.custhelp.com/app/answers/detail/a_id/4738) for details

**Recommendations:**
- Only enable this on development/testing machines
- Do not enable on production or multi-user systems
- Consider using the temporary method for one-time profiling sessions
- On shared systems, use elevated privileges (sudo) instead

## Alternative: Run as Root/Admin

If you cannot or should not modify system settings:

```bash
# Linux: Run with sudo
sudo ncu ./your_application

# Linux: Run with CAP_SYS_ADMIN capability
sudo setcap cap_sys_admin+ep $(which ncu)
ncu ./your_application
```

## Reference Links

- [Official NVIDIA ERR_NVGPUCTRPERM Documentation](https://developer.nvidia.com/ERR_NVGPUCTRPERM)
- [Nsight Compute Specific Guide](https://developer.nvidia.com/nvidia-development-tools-solutions-err-nvgpuctrperm-nsightcompute)
- [NVIDIA Security Notice](https://nvidia.custhelp.com/app/answers/detail/a_id/4738)
- [Using Nsight Compute in Containers](https://developer.nvidia.com/blog/using-nsight-compute-in-containers/)

## System Requirements

- **Linux:** Driver 418.43 or later
- **Windows:** Driver 419.17 or later
- **Supported OS:** Ubuntu, Debian, RHEL, CentOS, Fedora, SLES
- **Required:** Root/sudo access for configuration

## Common Use Cases

### Development Workstation
✅ **Use permanent configuration** - Most convenient for daily development

### Shared Server
⚠️ **Use sudo or temporary method** - Better security for multi-user systems

### CI/CD Pipeline
✅ **Run with sudo** - Simpler for automated testing

### Docker Container
✅ **Configure host permanently** - Apply once, use everywhere

## Related Tools

This configuration also enables other NVIDIA profiling tools:
- `nvprof` (legacy profiler)
- NVIDIA Visual Profiler
- Nsight Systems (for GPU metric sampling)
- Nsight Graphics
- CUPTI-based profiling tools
