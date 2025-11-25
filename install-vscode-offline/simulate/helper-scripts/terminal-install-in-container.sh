#!/bin/bash
#
# terminal-install-in-container.sh
#
# Install VS Code and extensions in the terminal container after it's built.
# This script is designed to be executed inside a running terminal container.
#
# Usage:
#   podman exec vscode-terminal bash /path/to/terminal-install-in-container.sh
#   or
#   podman cp helper-scripts/terminal-install-in-container.sh vscode-terminal:/tmp/
#   podman exec vscode-terminal bash /tmp/terminal-install-in-container.sh
#
# The script will:
#   1. Install VS Code from /pkgs-host/vscode-linux-*.tar.gz (if present)
#   2. Create /usr/local/bin/code symlink
#   3. Install all .vsix extensions found in /pkgs-host/
#   4. Set proper ownership for dev user
#

set -euo pipefail

# Configuration
PKGS_DIR="/pkgs-host"
INSTALL_USER="dev"
INSTALL_DIR="/home/${INSTALL_USER}/.local/vscode"
SYMLINK_PATH="/usr/local/bin/code"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
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

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    log_error "This script must be run as root (use podman exec without -u flag)"
    exit 1
fi

# Check if dev user exists
if ! id "${INSTALL_USER}" &>/dev/null; then
    log_error "User '${INSTALL_USER}' does not exist"
    exit 1
fi

echo "========================================="
echo "VS Code Terminal Container Installation"
echo "========================================="
echo ""
log_info "Install directory: ${INSTALL_DIR}"
log_info "Install user: ${INSTALL_USER}"
log_info "Packages directory: ${PKGS_DIR}"
echo ""

# Step 1: Install VS Code binary
echo "----------------------------------------"
log_info "Step 1: Installing VS Code binary"
echo "----------------------------------------"

VSCODE_TARBALL=$(find "${PKGS_DIR}" -maxdepth 1 -name "vscode-linux-*.tar.gz" | head -1)

if [ -z "${VSCODE_TARBALL}" ]; then
    log_warn "No VS Code tarball found in ${PKGS_DIR}"
    log_warn "Skipping VS Code installation"
else
    log_info "Found VS Code tarball: $(basename "${VSCODE_TARBALL}")"

    # Check if already installed
    if [ -d "${INSTALL_DIR}" ] && [ -f "${INSTALL_DIR}/bin/code" ]; then
        INSTALLED_VERSION=$(runuser -u "${INSTALL_USER}" -- "${INSTALL_DIR}/bin/code" --version 2>/dev/null | head -1 || echo "unknown")
        log_warn "VS Code is already installed at ${INSTALL_DIR}"
        log_info "Installed version: ${INSTALLED_VERSION}"
        read -p "Reinstall? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Skipping VS Code installation"
            VSCODE_TARBALL=""
        else
            log_info "Removing existing installation..."
            rm -rf "${INSTALL_DIR}"
        fi
    fi

    if [ -n "${VSCODE_TARBALL}" ]; then
        log_info "Creating installation directory..."
        mkdir -p "${INSTALL_DIR}"

        log_info "Extracting VS Code..."
        tar -xzf "${VSCODE_TARBALL}" -C "${INSTALL_DIR}" --strip-components=1

        log_info "Setting ownership to ${INSTALL_USER}..."
        chown -R "${INSTALL_USER}:${INSTALL_USER}" "${INSTALL_DIR}"

        log_success "VS Code installed to ${INSTALL_DIR}"

        # Display version
        if [ -f "${INSTALL_DIR}/bin/code" ]; then
            VERSION=$(runuser -u "${INSTALL_USER}" -- "${INSTALL_DIR}/bin/code" --version 2>/dev/null | head -1 || echo "unknown")
            log_info "Installed version: ${VERSION}"
        fi
    fi
fi

# Step 2: Create symlink
echo ""
echo "----------------------------------------"
log_info "Step 2: Creating code symlink"
echo "----------------------------------------"

if [ ! -f "${INSTALL_DIR}/bin/code" ]; then
    log_warn "VS Code binary not found at ${INSTALL_DIR}/bin/code"
    log_warn "Cannot create symlink"
elif [ -L "${SYMLINK_PATH}" ]; then
    CURRENT_TARGET=$(readlink "${SYMLINK_PATH}")
    if [ "${CURRENT_TARGET}" = "${INSTALL_DIR}/bin/code" ]; then
        log_info "Symlink already exists and points to correct location"
    else
        log_warn "Symlink exists but points to: ${CURRENT_TARGET}"
        log_info "Updating symlink..."
        ln -sf "${INSTALL_DIR}/bin/code" "${SYMLINK_PATH}"
        log_success "Symlink updated"
    fi
elif [ -f "${SYMLINK_PATH}" ]; then
    log_warn "${SYMLINK_PATH} exists but is not a symlink"
    log_warn "Backing up and creating symlink..."
    mv "${SYMLINK_PATH}" "${SYMLINK_PATH}.backup"
    ln -s "${INSTALL_DIR}/bin/code" "${SYMLINK_PATH}"
    log_success "Symlink created (old file backed up)"
else
    log_info "Creating symlink: ${SYMLINK_PATH} -> ${INSTALL_DIR}/bin/code"
    ln -s "${INSTALL_DIR}/bin/code" "${SYMLINK_PATH}"
    log_success "Symlink created"
fi

# Verify symlink
if command -v code &>/dev/null; then
    log_success "code command is available in PATH"
else
    log_warn "code command not found in PATH (symlink may not be in PATH)"
fi

# Step 3: Install extensions
echo ""
echo "----------------------------------------"
log_info "Step 3: Installing VS Code extensions"
echo "----------------------------------------"

# Find all .vsix files
mapfile -t VSIX_FILES < <(find "${PKGS_DIR}" -maxdepth 1 -name "*.vsix" | sort)

if [ ${#VSIX_FILES[@]} -eq 0 ]; then
    log_warn "No .vsix extension files found in ${PKGS_DIR}"
    log_warn "Skipping extension installation"
else
    log_info "Found ${#VSIX_FILES[@]} extension(s) to install"
    echo ""

    for VSIX in "${VSIX_FILES[@]}"; do
        VSIX_NAME=$(basename "${VSIX}")
        log_info "Installing: ${VSIX_NAME}"

        # Install as dev user with proper environment
        # Run as the install user directly, not via su -
        if runuser -u "${INSTALL_USER}" -- "${INSTALL_DIR}/bin/code" --install-extension "${VSIX}" --force &>/tmp/vsix-install.log; then
            log_success "  ✓ ${VSIX_NAME} installed"
        else
            log_error "  ✗ Failed to install ${VSIX_NAME}"
            if [ -f /tmp/vsix-install.log ]; then
                log_info "  Error details:"
                head -5 /tmp/vsix-install.log | sed 's/^/    /'
            fi
        fi
    done

    echo ""
    log_info "Listing installed extensions:"
    runuser -u "${INSTALL_USER}" -- "${INSTALL_DIR}/bin/code" --list-extensions 2>/dev/null | while read -r ext; do
        echo "  - ${ext}"
    done
fi

# Step 4: Summary
echo ""
echo "========================================="
log_success "Installation Complete!"
echo "========================================="
echo ""

if [ -f "${INSTALL_DIR}/bin/code" ]; then
    log_info "VS Code location: ${INSTALL_DIR}/bin/code"
    log_info "Command: code (via ${SYMLINK_PATH})"

    echo ""
    log_info "To launch VS Code GUI (from host):"
    echo "  podman exec -it vscode-terminal bash -c \"code --disable-gpu --no-sandbox --disable-dev-shm-usage\""

    echo ""
    log_info "To list installed extensions:"
    echo "  podman exec vscode-terminal code --list-extensions"
else
    log_warn "VS Code was not installed"
fi

echo ""
log_info "Installation log complete"
