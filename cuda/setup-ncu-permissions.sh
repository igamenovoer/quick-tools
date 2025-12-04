#!/bin/bash
set -e

# Script to configure Linux system permissions for NVIDIA Nsight Compute (ncu) profiling
# This addresses the ERR_NVGPUCTRPERM error by enabling GPU Performance Counter access

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;36m'
NC='\033[0m' # No Color

# Function to print colored messages
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_section() {
    echo -e "\n${BLUE}==== $1 ====${NC}\n"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    print_error "This script must be run as root or with sudo"
    exit 1
fi

print_section "NVIDIA Nsight Compute (ncu) Permission Setup"

print_info "This script will configure your system to allow GPU Performance Counter access"
print_info "for all users, which is required for ncu profiling."
print_info ""
print_warning "Note: This is done for security reasons. See NVIDIA Security Notice:"
print_warning "https://nvidia.custhelp.com/app/answers/detail/a_id/4738"
print_info ""

# Check if NVIDIA driver is installed
if ! command -v nvidia-smi &> /dev/null; then
    print_error "NVIDIA driver not found. Please install NVIDIA drivers first."
    exit 1
fi

# Get driver version
DRIVER_VERSION=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -n 1)
print_info "Detected NVIDIA Driver version: $DRIVER_VERSION"

# Parse command line arguments
PERMANENT=true

while [[ $# -gt 0 ]]; do
    case $1 in
        --temporary)
            PERMANENT=false
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --temporary           Apply changes temporarily (until reboot)"
            echo "  --help                Show this help message"
            echo ""
            echo "By default, this script makes permanent changes that require a reboot."
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

if [ "$PERMANENT" = true ]; then
    print_section "Applying Permanent Configuration"
    
    # Configuration file path
    MODPROBE_CONF="/etc/modprobe.d/nvidia-performance-counters.conf"
    
    print_info "Creating modprobe configuration file: $MODPROBE_CONF"
    
    # Create the configuration file
    cat > "$MODPROBE_CONF" << 'EOF'
# NVIDIA GPU Performance Counter Access Configuration
# This allows non-admin users to access GPU performance counters
# Required for NVIDIA Nsight Compute (ncu) profiling
# See: https://developer.nvidia.com/ERR_NVGPUCTRPERM

# Enable performance counter access for all users
options nvidia NVreg_RestrictProfilingToAdminUsers=0
options nvidia_drm NVreg_RestrictProfilingToAdminUsers=0
options nvidia_modeset NVreg_RestrictProfilingToAdminUsers=0
options nvidia_uvm NVreg_RestrictProfilingToAdminUsers=0
EOF
    
    print_info "Configuration file created successfully"
    
    # Detect distribution and rebuild initramfs
    print_info "Rebuilding initramfs to include new configuration..."
    
    if command -v update-initramfs &> /dev/null; then
        # Debian-based (Ubuntu, Debian, etc.)
        print_info "Detected Debian-based system, using update-initramfs"
        update-initramfs -u -k all
        print_info "Initramfs rebuilt successfully"
    elif command -v dracut &> /dev/null; then
        # RedHat-based (RHEL, CentOS, Fedora, etc.)
        print_info "Detected RedHat-based system, using dracut"
        dracut --regenerate-all -f
        print_info "Initramfs rebuilt successfully"
    else
        print_warning "Could not detect initramfs tool (update-initramfs or dracut)"
        print_warning "You may need to rebuild initramfs manually"
    fi
    
    print_info ""
    print_info "✓ Permanent configuration applied"
    print_warning ""
    print_warning "⚠️  REBOOT REQUIRED for changes to take effect!"
    print_warning ""
    print_info "Please reboot your system manually to apply the new settings."
    
else
    print_section "Applying Temporary Configuration"
    
    print_warning "Temporary mode will unload all NVIDIA kernel modules!"
    print_warning "This will stop your display manager and close any GPU applications."
    print_warning ""
    echo -e "${YELLOW}Do you want to continue? [y/N]${NC} "
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        print_info "Operation cancelled"
        exit 0
    fi
    
    # Stop display manager if running
    print_info "Stopping display manager..."
    if systemctl is-active --quiet graphical.target; then
        systemctl isolate multi-user.target
        RESTORE_GRAPHICAL=true
    else
        RESTORE_GRAPHICAL=false
    fi
    
    # Unload NVIDIA kernel modules
    print_info "Unloading NVIDIA kernel modules..."
    
    # Check if modules are in use
    if lsof /dev/nvidia* &> /dev/null; then
        print_warning "Some processes are still using NVIDIA devices:"
        lsof /dev/nvidia* | head -n 20
        print_error "Please close all GPU applications and try again"
        if [ "$RESTORE_GRAPHICAL" = true ]; then
            systemctl isolate graphical.target
        fi
        exit 1
    fi
    
    # Try to unload modules
    if ! modprobe -rf nvidia_uvm nvidia_drm nvidia_modeset nvidia-vgpu-vfio nvidia; then
        print_error "Failed to unload NVIDIA kernel modules"
        print_info "Some processes may still be using the GPU"
        if [ "$RESTORE_GRAPHICAL" = true ]; then
            systemctl isolate graphical.target
        fi
        exit 1
    fi
    
    print_info "NVIDIA modules unloaded successfully"
    
    # Load modules with new parameters
    print_info "Loading NVIDIA modules with performance counter access enabled..."
    modprobe nvidia NVreg_RestrictProfilingToAdminUsers=0
    
    # Restore display manager if it was running
    if [ "$RESTORE_GRAPHICAL" = true ]; then
        print_info "Restoring display manager..."
        systemctl isolate graphical.target
    fi
    
    print_info ""
    print_info "✓ Temporary configuration applied successfully"
    print_warning "⚠️  Changes will be lost after reboot!"
    print_info "To make changes permanent, run this script without --temporary flag"
fi

print_section "Verification"

# Verify the current setting
if [ -f "/proc/driver/nvidia/params" ]; then
    CURRENT_SETTING=$(grep "RmProfilingAdminOnly" /proc/driver/nvidia/params | awk '{print $2}')
    
    if [ "$CURRENT_SETTING" = "0" ]; then
        print_info "✓ GPU Performance Counters are accessible to all users"
    elif [ "$CURRENT_SETTING" = "1" ]; then
        print_warning "⚠ GPU Performance Counters are still restricted to admin users"
        print_warning "A reboot may be required for permanent changes to take effect"
    else
        print_warning "Could not determine current profiling restriction status"
    fi
else
    print_warning "/proc/driver/nvidia/params not found"
    print_info "This is normal if the configuration hasn't been applied yet"
fi

# Check if initramfs includes the configuration (for permanent mode)
if [ "$PERMANENT" = true ]; then
    print_info ""
    print_info "Checking if configuration is included in initramfs..."
    
    if command -v lsinitramfs &> /dev/null; then
        if lsinitramfs /boot/initrd.img 2>/dev/null | grep -q "nvidia-performance-counters.conf"; then
            print_info "✓ Configuration found in initramfs"
        else
            print_warning "Configuration not found in initramfs (this may be normal)"
        fi
    elif command -v lsinitrd &> /dev/null; then
        if lsinitrd 2>/dev/null | grep -q "nvidia-performance-counters.conf"; then
            print_info "✓ Configuration found in initramfs"
        else
            print_warning "Configuration not found in initramfs (this may be normal)"
        fi
    fi
fi

print_section "Testing ncu"

# Test if ncu is available
if command -v ncu &> /dev/null; then
    NCU_VERSION=$(ncu --version | head -n 1)
    print_info "NVIDIA Nsight Compute detected: $NCU_VERSION"
    
    if [ "$PERMANENT" = false ] || [ "$CURRENT_SETTING" = "0" ]; then
        print_info ""
        print_info "You can now test ncu profiling with a simple command like:"
        print_info "  ncu --query-metrics"
        print_info "  ncu ./your_cuda_application"
    fi
else
    print_warning "ncu command not found in PATH"
    print_info "Install NVIDIA Nsight Compute to use GPU profiling"
    print_info "It's typically installed as part of CUDA Toolkit"
fi

print_section "Summary"

if [ "$PERMANENT" = true ]; then
    print_info "Configuration file created: $MODPROBE_CONF"
    print_info "Initramfs has been rebuilt"
    print_warning "⚠️  Please REBOOT your system for changes to take effect"
else
    print_info "Temporary configuration applied (until next reboot)"
fi

print_info ""
print_info "For more information, visit:"
print_info "  https://developer.nvidia.com/ERR_NVGPUCTRPERM"
print_info ""

print_info "✓ Setup complete!"
