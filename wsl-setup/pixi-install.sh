#!/bin/bash

# setup-pixi.sh - Automatically install the latest version of Pixi Python package manager
# Author: Auto-generated script
# Description: Downloads and installs the latest version of Pixi from the official source
# Usage: ./setup-pixi.sh [--force] [--version VERSION] [--help]

set -euo pipefail

# Default values
FORCE_INSTALL=false
SPECIFIC_VERSION=""
SHOW_HELP=false

# Function to show help
show_help() {
    cat << EOF
Pixi Python Package Manager Installer

Usage: $0 [OPTIONS]

OPTIONS:
    --force         Force installation even if Pixi is already installed
    --version VER   Install a specific version (e.g., v0.55.0)
    --help          Show this help message

EXAMPLES:
    $0                           # Install latest version
    $0 --force                   # Force install latest version
    $0 --version v0.54.0         # Install specific version
    $0 --force --version v0.54.0 # Force install specific version

For more information about Pixi, visit: https://pixi.sh/
EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                FORCE_INSTALL=true
                shift
                ;;
            --version)
                SPECIFIC_VERSION="$2"
                shift 2
                ;;
            --help|-h)
                SHOW_HELP=true
                shift
                ;;
            *)
                print_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
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

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to get the latest version from GitHub API
get_latest_version() {
    print_info "Fetching latest Pixi version information..."
    
    if command_exists curl; then
        latest_version=$(curl -s https://api.github.com/repos/prefix-dev/pixi/releases/latest | grep '"tag_name":' | sed -E 's/.*"tag_name": "([^"]+)".*/\1/')
    elif command_exists wget; then
        latest_version=$(wget -qO- https://api.github.com/repos/prefix-dev/pixi/releases/latest | grep '"tag_name":' | sed -E 's/.*"tag_name": "([^"]+)".*/\1/')
    else
        print_error "Neither curl nor wget is available. Please install one of them."
        exit 1
    fi
    
    if [[ -z "$latest_version" ]]; then
        print_warning "Could not fetch latest version. Using fallback method..."
        latest_version="latest"
    else
        print_info "Latest version: $latest_version"
    fi
    
    echo "$latest_version"
}

# Function to check if Pixi is already installed
check_existing_installation() {
    if command_exists pixi; then
        current_version=$(pixi --version 2>/dev/null | awk '{print $2}' || echo "unknown")
        print_info "Pixi is already installed (version: $current_version)"
        
        if [[ "$FORCE_INSTALL" == "true" ]]; then
            print_info "Force installation requested. Proceeding with installation..."
            return 0
        fi
        
        read -p "Do you want to reinstall/upgrade Pixi? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Installation cancelled by user."
            exit 0
        fi
    fi
}

# Function to create backup of existing installation
backup_existing() {
    if [[ -f "$HOME/.pixi/bin/pixi" ]]; then
        print_info "Creating backup of existing Pixi installation..."
        cp "$HOME/.pixi/bin/pixi" "$HOME/.pixi/bin/pixi.backup.$(date +%Y%m%d_%H%M%S)" || true
    fi
}

# Function to install Pixi using the official installer
install_pixi() {
    print_info "Starting Pixi installation..."
    
    # Create temporary directory
    temp_dir=$(mktemp -d)
    cd "$temp_dir"
    
    print_info "Downloading Pixi installer script..."
    
    # Determine installer URL based on version
    if [[ -n "$SPECIFIC_VERSION" ]]; then
        print_info "Installing specific version: $SPECIFIC_VERSION"
        # For specific versions, we'll need to modify the installer or use direct download
        export PIXI_VERSION="$SPECIFIC_VERSION"
    fi
    
    if command_exists curl; then
        curl -fsSL https://pixi.sh/install.sh -o install.sh
    elif command_exists wget; then
        wget -q https://pixi.sh/install.sh -O install.sh
    else
        print_error "Neither curl nor wget is available. Cannot download installer."
        exit 1
    fi
    
    # Make the script executable
    chmod +x install.sh
    
    print_info "Running Pixi installer..."
    
    # Set environment variable for specific version if requested
    if [[ -n "$SPECIFIC_VERSION" ]]; then
        export PIXI_VERSION="$SPECIFIC_VERSION"
    fi
    
    # Run the installer
    if bash install.sh; then
        print_success "Pixi installer completed successfully!"
    else
        print_error "Pixi installation failed!"
        exit 1
    fi
    
    # Clean up
    cd - > /dev/null
    rm -rf "$temp_dir"
}

# Function to verify installation
verify_installation() {
    print_info "Verifying Pixi installation..."
    
    # Source the shell configuration to update PATH
    if [[ -f "$HOME/.bashrc" ]]; then
        source "$HOME/.bashrc" 2>/dev/null || true
    fi
    
    # Check if pixi binary exists
    if [[ -f "$HOME/.pixi/bin/pixi" ]]; then
        export PATH="$HOME/.pixi/bin:$PATH"
    fi
    
    if command_exists pixi; then
        version=$(pixi --version 2>/dev/null | awk '{print $2}' || echo "unknown")
        print_success "Pixi installed successfully! Version: $version"
        
        # Test basic functionality
        print_info "Testing Pixi functionality..."
        if pixi --help >/dev/null 2>&1; then
            print_success "Pixi is working correctly!"
        else
            print_warning "Pixi installed but may not be working correctly."
        fi
    else
        print_error "Pixi installation verification failed!"
        print_warning "Please restart your terminal or run: source ~/.bashrc"
        exit 1
    fi
}

# Function to update PATH in shell configuration
update_shell_config() {
    print_info "Updating shell configuration..."
    
    # The installer script should handle this, but let's ensure it's set
    pixi_bin_path="$HOME/.pixi/bin"
    
    # Check if PATH is already updated
    if [[ ":$PATH:" != *":$pixi_bin_path:"* ]]; then
        print_info "Adding Pixi to PATH in shell configuration..."
        
        # Update .bashrc if it exists
        if [[ -f "$HOME/.bashrc" ]]; then
            if ! grep -q "\.pixi/bin" "$HOME/.bashrc"; then
                echo 'export PATH="$HOME/.pixi/bin:$PATH"' >> "$HOME/.bashrc"
                print_info "Updated ~/.bashrc"
            fi
        fi
        
        # Update .zshrc if it exists (for zsh users)
        if [[ -f "$HOME/.zshrc" ]]; then
            if ! grep -q "\.pixi/bin" "$HOME/.zshrc"; then
                echo 'export PATH="$HOME/.pixi/bin:$PATH"' >> "$HOME/.zshrc"
                print_info "Updated ~/.zshrc"
            fi
        fi
        
        # Update current session
        export PATH="$pixi_bin_path:$PATH"
    fi
}

# Function to display post-installation information
show_post_install_info() {
    print_success "Pixi installation completed!"
    echo
    print_info "Getting started with Pixi:"
    echo "  1. Restart your terminal or run: source ~/.bashrc"
    echo "  2. Initialize a new project: pixi init my-project"
    echo "  3. Add dependencies: pixi add python numpy"
    echo "  4. Run commands: pixi run python"
    echo
    print_info "Documentation: https://pixi.sh/"
    print_info "GitHub: https://github.com/prefix-dev/pixi"
    echo
}

# Main execution function
main() {
    # Parse command line arguments first
    parse_args "$@"
    
    # Show help if requested
    if [[ "$SHOW_HELP" == "true" ]]; then
        show_help
        exit 0
    fi
    
    echo "======================================"
    print_info "Pixi Python Package Manager Installer"
    echo "======================================"
    echo
    
    # Check system requirements
    print_info "Checking system requirements..."
    
    if ! command_exists curl && ! command_exists wget; then
        print_error "Neither curl nor wget is installed. Please install one of them first."
        print_info "On Ubuntu/Debian: sudo apt update && sudo apt install curl"
        print_info "On CentOS/RHEL: sudo yum install curl"
        exit 1
    fi
    
    # Get latest version info (unless specific version is requested)
    if [[ -z "$SPECIFIC_VERSION" ]]; then
        latest_version=$(get_latest_version)
    else
        print_info "Specific version requested: $SPECIFIC_VERSION"
    fi
    
    # Check for existing installation
    check_existing_installation
    
    # Backup existing installation if any
    backup_existing
    
    # Install Pixi
    install_pixi
    
    # Update shell configuration
    update_shell_config
    
    # Verify installation
    verify_installation
    
    # Show post-installation information
    show_post_install_info
    
    print_success "All done! Enjoy using Pixi!"
}

# Error handling
trap 'print_error "An error occurred. Installation may be incomplete."' ERR

# Run main function
main "$@"