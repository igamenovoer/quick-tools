#!/bin/bash
#
# install-vscode-server-on-remote.sh
#
# Install VS Code Server on the remote container for Remote-SSH connections.
# This script solves the "Failed to download VS Code Server" error in air-gapped environments.
#
# Usage:
#   podman exec -u vscode-tester vscode-remote bash /path/to/install-vscode-server-on-remote.sh
#

set -euo pipefail

# Configuration
VSCODE_COMMIT="1e3c50d64110be466c0b4a45222e81d2c9352888"
VSCODE_VERSION="1.106.2"
INSTALL_DIR="$HOME/.vscode-server"
SERVER_DIR="${INSTALL_DIR}/cli/servers/Stable-${VSCODE_COMMIT}/server"
DOWNLOAD_URL="https://update.code.visualstudio.com/commit:${VSCODE_COMMIT}/server-linux-x64/stable"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

echo "========================================="
echo "VS Code Server Installation"
echo "========================================="
echo ""
log_info "VS Code Version: ${VSCODE_VERSION}"
log_info "VS Code Commit: ${VSCODE_COMMIT}"
log_info "Install Directory: ${SERVER_DIR}"
echo ""

# Check if already installed
if [ -d "${SERVER_DIR}" ] && [ -f "${SERVER_DIR}/bin/code-server" ]; then
    log_success "VS Code Server is already installed!"
    log_info "Location: ${SERVER_DIR}"
    log_info "To reinstall, delete the directory and run this script again:"
    log_info "  rm -rf ${SERVER_DIR}"
    exit 0
fi

# Create directory structure
log_info "Creating directory structure..."
mkdir -p "${SERVER_DIR}"
mkdir -p "${INSTALL_DIR}/data/Machine"
mkdir -p "${INSTALL_DIR}/extensions"

# Check if tarball exists in /pkgs-host/
PKGS_TARBALL="/pkgs-host/vscode-server-linux-x64-${VSCODE_COMMIT}.tar.gz"
if [ -f "${PKGS_TARBALL}" ]; then
    log_info "Found VS Code Server tarball in /pkgs-host/"
    log_info "Extracting from: ${PKGS_TARBALL}"
    tar -xzf "${PKGS_TARBALL}" -C "${SERVER_DIR}" --strip-components=1
    log_success "VS Code Server extracted successfully"
else
    log_warn "VS Code Server tarball not found in /pkgs-host/"
    log_warn "Expected: ${PKGS_TARBALL}"
    echo ""

    # Check if we have internet (for non-airgap testing)
    if command -v curl >/dev/null 2>&1 && curl -s --connect-timeout 5 https://update.code.visualstudio.com >/dev/null 2>&1; then
        log_info "Internet connection detected. Downloading VS Code Server..."
        log_info "Download URL: ${DOWNLOAD_URL}"

        TEMP_TARBALL="/tmp/vscode-server-${VSCODE_COMMIT}.tar.gz"
        curl -fL "${DOWNLOAD_URL}" -o "${TEMP_TARBALL}"

        log_info "Extracting to: ${SERVER_DIR}"
        tar -xzf "${TEMP_TARBALL}" -C "${SERVER_DIR}" --strip-components=1
        rm -f "${TEMP_TARBALL}"

        log_success "VS Code Server downloaded and installed successfully"
    else
        log_error "Cannot download VS Code Server (no internet access)"
        echo ""
        echo "=============================================="
        echo "Manual Installation Required"
        echo "=============================================="
        echo ""
        echo "1. On a machine with internet, download VS Code Server:"
        echo "   wget ${DOWNLOAD_URL} -O vscode-server-linux-x64-${VSCODE_COMMIT}.tar.gz"
        echo ""
        echo "2. Copy the tarball to the pkgs directory:"
        echo "   cp vscode-server-linux-x64-${VSCODE_COMMIT}.tar.gz \\"
        echo "      install-vscode-offline/simulate/pkgs/"
        echo ""
        echo "3. The file will be available in the container at:"
        echo "   /pkgs-host/vscode-server-linux-x64-${VSCODE_COMMIT}.tar.gz"
        echo ""
        echo "4. Run this script again"
        echo ""
        exit 1
    fi
fi

# Verify installation
if [ -f "${SERVER_DIR}/bin/code-server" ]; then
    log_success "VS Code Server installed successfully!"
    log_info "Server binary: ${SERVER_DIR}/bin/code-server"

    # Create necessary files
    log_info "Creating configuration files..."

    # Create machine settings
    echo '{}' > "${INSTALL_DIR}/data/Machine/settings.json"

    # Mark server as ready
    touch "${SERVER_DIR}/.ready"

    echo ""
    echo "========================================="
    log_success "Installation Complete!"
    echo "========================================="
    echo ""
    log_info "VS Code Remote-SSH should now work without internet"
    log_info "Connect from VS Code using:"
    echo "  - Host: vscode-remote"
    echo "  - User: vscode-tester"
    echo ""
else
    log_error "Installation failed - code-server binary not found"
    exit 1
fi
