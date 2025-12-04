#!/bin/bash

# Quick CUDA Repository Setup for Ubuntu (Auto-detect version)
# Automatically detects Ubuntu version and finds the correct keyring file
# Usage: ./quick_cuda_repo.sh [--dry-run]

set -e

# Parse command line arguments
DRY_RUN=false
MANUAL_VERSION=""
for arg in "$@"; do
    case $arg in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --system-version=*)
            MANUAL_VERSION="${arg#*=}"
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [--dry-run] [--system-version=VERSION]"
            echo ""
            echo "Options:"
            echo "  --dry-run              Only detect and show information, don't modify system"
            echo "  --system-version=VER   Manually specify Ubuntu version (e.g., 24.04, 22.04, 20.04)"
            echo "                         Use this if lsb_release is not available or to override detection"
            echo "  -h, --help             Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0 --dry-run"
            echo "  $0 --system-version=22.04"
            echo "  $0 --system-version=24.04 --dry-run"
            exit 0
            ;;
        *)
            echo "Unknown option: $arg"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Check if running on Ubuntu (unless manual version is specified)
if [ -z "$MANUAL_VERSION" ]; then
    if ! command -v lsb_release &> /dev/null; then
        echo "❌ Error: lsb_release not found and no manual version specified"
        echo "Please install lsb-release package or use --system-version=VERSION"
        echo "Example: $0 --system-version=24.04"
        exit 1
    fi
    
    # Auto-detect Ubuntu version
    UBUNTU_VERSION=$(lsb_release -rs)
    UBUNTU_CODENAME=$(lsb_release -cs)
    echo "Detected Ubuntu $UBUNTU_VERSION ($UBUNTU_CODENAME)"
else
    # Use manually specified version
    UBUNTU_VERSION="$MANUAL_VERSION"
    echo "Using manually specified Ubuntu version: $UBUNTU_VERSION"
fi

echo "Adding NVIDIA CUDA repository..."

# Function to convert Ubuntu version to repository format (e.g., 24.04 -> ubuntu2404)
get_repo_name() {
    local version="$1"
    # Remove dots and convert to ubuntuXXXX format
    echo "ubuntu$(echo "$version" | tr -d '.')"
}

# Dynamically find available Ubuntu repositories
echo "Checking available Ubuntu repositories..."
AVAILABLE_REPOS=$(curl -s https://developer.download.nvidia.com/compute/cuda/repos/ | grep -o "href='ubuntu[0-9]*/" | sed "s/href='//g" | sed "s/\///g")

# Convert current Ubuntu version to repository format
REPO_NAME=$(get_repo_name "$UBUNTU_VERSION")

# Check if the repository exists for current Ubuntu version
if echo "$AVAILABLE_REPOS" | grep -q "^$REPO_NAME$"; then
    REPO_URL="https://developer.download.nvidia.com/compute/cuda/repos/$REPO_NAME/x86_64"
    echo "✅ Found repository for Ubuntu $UBUNTU_VERSION: $REPO_NAME"
else
    echo "❌ Error: No CUDA repository found for Ubuntu $UBUNTU_VERSION"
    echo ""
    echo "Available Ubuntu versions:"
    echo "$AVAILABLE_REPOS" | sed 's/ubuntu//g' | sed 's/\(..\)\(..\)/\1.\2/' | sort -V | sed 's/^/  - /'
    echo ""
    echo "Consider using a supported version or check if NVIDIA has added support."
    exit 1
fi

# Find the keyring file dynamically
echo "Finding CUDA keyring package..."
KEYRING_FILE=$(curl -s "$REPO_URL/" | grep -o "href='cuda-keyring_[^']*\.deb'" | sed "s/href='//g" | sed "s/'//g" | sort -V | tail -1)

if [ -z "$KEYRING_FILE" ]; then
    echo "❌ Error: Could not find CUDA keyring package"
    exit 1
fi

echo "Found keyring: $KEYRING_FILE"

if [ "$DRY_RUN" = true ]; then
    echo ""
    echo "🔍 DRY RUN MODE - No system modifications will be made"
    echo ""
    echo "Repository URL: $REPO_URL"
    echo "Keyring file: $KEYRING_FILE"
    echo "Full URL: ${REPO_URL}/${KEYRING_FILE}"
    echo ""
    echo "To actually install, run without --dry-run flag"
    exit 0
fi

# Download and install CUDA keyring
wget "${REPO_URL}/${KEYRING_FILE}"
sudo dpkg -i "$KEYRING_FILE"

# Update package cache
echo "Updating package cache..."
sudo apt update

# Clean up
rm "$KEYRING_FILE"

echo "✅ CUDA repository added successfully!"
echo ""
echo "Install CUDA with:"
echo "  sudo apt install cuda-toolkit"
echo ""
echo "Available packages:"
apt search cuda-toolkit 2>/dev/null | grep "^cuda-toolkit" | head -3
