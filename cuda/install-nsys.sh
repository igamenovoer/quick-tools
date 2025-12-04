#!/bin/bash
set -e

# Script to install NVIDIA Nsight Systems (nsys) non-interactively
# Supports both x86_64 and ARM64 architectures

NSYS_VERSION="2025.5.1"
NSYS_BUILD="121-3638078"
NSYS_DEB_VERSION="2025.5.1.121-1"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Detect architecture
ARCH=$(dpkg --print-architecture)
if [ "$ARCH" != "amd64" ] && [ "$ARCH" != "arm64" ]; then
    echo -e "${RED}Error: Unsupported architecture: $ARCH${NC}"
    echo "This script supports amd64 (x86_64) and arm64 only."
    exit 1
fi

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

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    print_error "This script must be run as root or with sudo"
    exit 1
fi

# Parse command line arguments
INSTALL_CLI_ONLY=false
INSTALL_METHOD="deb"

while [[ $# -gt 0 ]]; do
    case $1 in
        --cli-only)
            INSTALL_CLI_ONLY=true
            shift
            ;;
        --method)
            INSTALL_METHOD="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --cli-only        Install CLI-only version (no GUI)"
            echo "  --method METHOD   Installation method: 'deb' or 'run' (default: deb)"
            echo "  --help            Show this help message"
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

print_info "Starting NVIDIA Nsight Systems installation..."
print_info "Version: $NSYS_VERSION"
print_info "Architecture: $ARCH"

# Create temporary directory
TMP_DIR=$(mktemp -d)
trap "rm -rf $TMP_DIR" EXIT

cd "$TMP_DIR"

# Set download URLs based on architecture and installation type
if [ "$ARCH" = "amd64" ]; then
    if [ "$INSTALL_CLI_ONLY" = true ]; then
        DEB_URL="https://developer.nvidia.com/downloads/assets/tools/secure/nsight-systems/2025_5/NsightSystems-linux-cli-public-${NSYS_VERSION}.${NSYS_BUILD}.deb"
        DEB_FILE="nsight-systems-cli.deb"
    else
        if [ "$INSTALL_METHOD" = "deb" ]; then
            DEB_URL="https://developer.nvidia.com/downloads/assets/tools/secure/nsight-systems/2025_5/nsight-systems-${NSYS_VERSION}_${NSYS_DEB_VERSION}_${ARCH}.deb"
            DEB_FILE="nsight-systems.deb"
        else
            RUN_URL="https://developer.nvidia.com/downloads/assets/tools/secure/nsight-systems/2025_5/NsightSystems-linux-public-${NSYS_VERSION}.${NSYS_BUILD}.run"
            RUN_FILE="nsight-systems.run"
        fi
    fi
elif [ "$ARCH" = "arm64" ]; then
    if [ "$INSTALL_CLI_ONLY" = true ]; then
        DEB_URL="https://developer.nvidia.com/downloads/assets/tools/secure/nsight-systems/2025_5/nsight-systems-cli-${NSYS_VERSION}_${NSYS_DEB_VERSION}_${ARCH}.deb"
        DEB_FILE="nsight-systems-cli.deb"
    else
        if [ "$INSTALL_METHOD" = "deb" ]; then
            DEB_URL="https://developer.nvidia.com/downloads/assets/tools/secure/nsight-systems/2025_5/nsight-systems-${NSYS_VERSION}_${NSYS_DEB_VERSION}_${ARCH}.deb"
            DEB_FILE="nsight-systems.deb"
        else
            RUN_URL="https://developer.nvidia.com/downloads/assets/tools/secure/nsight-systems/2025_5/NsightSystems-linux-sbsa-public-${NSYS_VERSION}.${NSYS_BUILD}.run"
            RUN_FILE="nsight-systems.run"
        fi
    fi
fi

# Check if nsys is already installed
if command -v nsys &> /dev/null; then
    INSTALLED_VERSION=$(nsys --version 2>&1 | grep -oP 'Nsight Systems version \K[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")
    print_warning "nsys is already installed (version: $INSTALLED_VERSION)"
    read -p "Do you want to continue with installation? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Installation cancelled."
        exit 0
    fi
fi

# Download and install
if [ "$INSTALL_METHOD" = "deb" ]; then
    print_info "Downloading Nsight Systems .deb package..."
    print_info "URL: $DEB_URL"
    
    if ! wget -q --show-progress "$DEB_URL" -O "$DEB_FILE"; then
        print_error "Failed to download Nsight Systems package"
        print_info "Please check your internet connection and try again"
        exit 1
    fi
    
    print_info "Installing Nsight Systems..."
    export DEBIAN_FRONTEND=noninteractive
    
    if ! dpkg -i "$DEB_FILE" 2>/dev/null; then
        print_warning "dpkg reported issues, attempting to fix dependencies..."
        apt-get update -qq
        apt-get install -f -y -qq
    fi
    
    print_info "Installation complete!"
    
else  # run method
    print_info "Downloading Nsight Systems .run installer..."
    print_info "URL: $RUN_URL"
    
    if ! wget -q --show-progress "$RUN_URL" -O "$RUN_FILE"; then
        print_error "Failed to download Nsight Systems installer"
        print_info "Please check your internet connection and try again"
        exit 1
    fi
    
    chmod +x "$RUN_FILE"
    
    print_info "Installing Nsight Systems..."
    # Run installer in non-interactive mode
    if ! ./"$RUN_FILE" --nox11 --quiet -- --accept; then
        print_error "Installation failed"
        exit 1
    fi
    
    print_info "Installation complete!"
fi

# Verify installation
print_info "Verifying installation..."
if command -v nsys &> /dev/null; then
    INSTALLED_VERSION=$(nsys --version 2>&1 | head -n 1)
    print_info "Successfully installed: $INSTALLED_VERSION"
    
    # Run environment check
    print_info "Running environment check..."
    nsys status -e || print_warning "Environment check showed some warnings (this may be normal)"
else
    print_error "Installation verification failed - nsys command not found"
    print_info "You may need to add nsys to your PATH or restart your shell"
    exit 1
fi

print_info "NVIDIA Nsight Systems installation completed successfully!"
print_info ""
print_info "Usage examples:"
print_info "  nsys --version              # Check version"
print_info "  nsys status -e              # Check environment"
print_info "  nsys profile ./your_app     # Profile an application"
print_info ""
print_info "For more information, visit: https://docs.nvidia.com/nsight-systems/"
