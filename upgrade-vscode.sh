#!/bin/bash

# upgrade-vscode.sh - Download and install the latest VS Code .deb package
# Requires sudo privileges to execute

set -e  # Exit on any error

# Check if running with sudo
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run with sudo privileges"
    echo "Usage: sudo ./upgrade-vscode.sh"
    exit 1
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Variables
DOWNLOAD_URL="https://code.visualstudio.com/sha/download?build=stable&os=linux-deb-x64"
TEMP_DIR="/tmp"
DEB_FILE="$TEMP_DIR/code_latest_amd64.deb"

print_status "Starting VS Code upgrade process..."

# Check if wget is available
if ! command -v wget &> /dev/null; then
    print_error "wget is not installed. Please install wget first:"
    print_error "sudo apt update && sudo apt install wget"
    exit 1
fi

# Check if dpkg is available
if ! command -v dpkg &> /dev/null; then
    print_error "dpkg is not available. This script is for Debian/Ubuntu systems only."
    exit 1
fi

# Remove old download if exists
if [ -f "$DEB_FILE" ]; then
    print_status "Removing previous download..."
    rm -f "$DEB_FILE"
fi

# Download the latest VS Code .deb package
print_status "Downloading latest VS Code .deb package..."
if wget -q --show-progress "$DOWNLOAD_URL" -O "$DEB_FILE"; then
    print_success "Download completed successfully"
else
    print_error "Failed to download VS Code package"
    exit 1
fi

# Verify the downloaded file
if [ ! -f "$DEB_FILE" ]; then
    print_error "Downloaded file not found"
    exit 1
fi

# Check file size (should be reasonably large for VS Code)
FILE_SIZE=$(stat -c%s "$DEB_FILE")
if [ "$FILE_SIZE" -lt 1000000 ]; then  # Less than 1MB is suspicious
    print_error "Downloaded file seems too small ($FILE_SIZE bytes). Download may have failed."
    exit 1
fi

print_status "Downloaded file size: $(numfmt --to=iec $FILE_SIZE)"

# Check if VS Code is currently installed
CURRENT_VERSION=""
if command -v code &> /dev/null; then
    CURRENT_VERSION=$(code --version 2>/dev/null | head -n1 || echo "Unknown")
    print_status "Current VS Code version: $CURRENT_VERSION"
else
    print_status "VS Code is not currently installed"
fi

# Update package database
print_status "Updating package database..."
apt update -qq

# Install dependencies if needed
print_status "Installing dependencies..."
apt install -f -y

# Install the VS Code package
print_status "Installing VS Code package..."
if dpkg -i "$DEB_FILE" 2>/dev/null; then
    print_success "VS Code package installed successfully"
else
    print_warning "dpkg installation encountered issues, attempting to fix..."
    # Fix broken dependencies
    apt install -f -y
    if dpkg -i "$DEB_FILE"; then
        print_success "VS Code package installed successfully after dependency fix"
    else
        print_error "Failed to install VS Code package"
        exit 1
    fi
fi

# Verify installation
if command -v code &> /dev/null; then
    NEW_VERSION=$(code --version 2>/dev/null | head -n1 || echo "Unknown")
    print_success "VS Code installation verified"
    print_success "New VS Code version: $NEW_VERSION"
    
    if [ -n "$CURRENT_VERSION" ] && [ "$CURRENT_VERSION" != "Unknown" ]; then
        if [ "$CURRENT_VERSION" != "$NEW_VERSION" ]; then
            print_success "Successfully upgraded from $CURRENT_VERSION to $NEW_VERSION"
        else
            print_success "VS Code was already up to date (version $NEW_VERSION)"
        fi
    fi
else
    print_error "VS Code installation verification failed"
    exit 1
fi

# Clean up
print_status "Cleaning up temporary files..."
rm -f "$DEB_FILE"
print_success "Cleanup completed"

# Add VS Code to applications menu (if not already done)
if [ ! -f "/usr/share/applications/code.desktop" ]; then
    print_status "Adding VS Code to applications menu..."
    # This is usually handled automatically by the package, but just in case
    update-desktop-database 2>/dev/null || true
fi

print_success "VS Code upgrade process completed successfully!"
print_status "You can now launch VS Code by typing 'code' in the terminal or from the applications menu"

# Optional: Show some useful information
echo ""
print_status "Useful VS Code information:"
echo "  - Config directory: ~/.config/Code/"
echo "  - Extensions directory: ~/.vscode/extensions/"
echo "  - Launch from terminal: code [file/directory]"
echo "  - Launch with specific workspace: code /path/to/workspace"
echo "  - Check version: code --version"
