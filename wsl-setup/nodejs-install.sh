#!/bin/bash

# Node.js and npm Setup Script using NVM
# This script installs NVM (Node Version Manager) and the latest LTS version of Node.js
# Uses the master branch for NVM installation to automatically get the latest version
# Last updated: September 2024
#
# Usage: ./setup-nodejs.sh [--yes|-y]
#        --yes, -y : Skip all confirmation prompts and proceed with installation

set -e  # Exit on any error

# Parse command line arguments
SKIP_CONFIRMATION=false
for arg in "$@"; do
    case $arg in
        --yes|-y)
            SKIP_CONFIRMATION=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [--yes|-y]"
            echo "  --yes, -y : Skip all confirmation prompts and proceed with installation"
            echo "  --help, -h : Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $arg"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

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

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to ask for user confirmation
ask_confirmation() {
    if [ "$SKIP_CONFIRMATION" = true ]; then
        return 0  # Always proceed if --yes flag is used
    fi
    
    local message="$1"
    local default_answer="${2:-y}"
    
    if [ "$default_answer" = "y" ]; then
        echo -n "$message [Y/n]: "
    else
        echo -n "$message [y/N]: "
    fi
    
    read -r response
    response=${response:-$default_answer}
    
    case "$response" in
        [yY][eE][sS]|[yY])
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Check if running on Ubuntu/Debian-based system
if ! command_exists apt; then
    print_error "This script is designed for Ubuntu/Debian-based systems with apt package manager."
    exit 1
fi

print_status "Starting Node.js and npm installation using NVM..."

# Check if NVM is already installed
NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
if [ -d "$NVM_DIR" ] || command_exists nvm; then
    print_warning "NVM appears to be already installed in $NVM_DIR"
    
    # Try to get current NVM version if possible
    if [ -s "$NVM_DIR/nvm.sh" ]; then
        source "$NVM_DIR/nvm.sh"
        if command_exists nvm; then
            CURRENT_NVM_VERSION=$(nvm --version 2>/dev/null || echo "unknown")
            print_status "Current NVM version: $CURRENT_NVM_VERSION"
        fi
    fi
    
    if ask_confirmation "Do you want to reinstall/update NVM? This will overwrite the existing installation"; then
        print_status "Proceeding with NVM reinstallation..."
        # Backup existing NVM directory if it exists
        if [ -d "$NVM_DIR" ]; then
            BACKUP_DIR="${NVM_DIR}.backup.$(date +%Y%m%d_%H%M%S)"
            print_status "Creating backup at $BACKUP_DIR..."
            cp -r "$NVM_DIR" "$BACKUP_DIR"
        fi
    else
        print_status "Skipping NVM installation. Using existing NVM..."
        # Source existing NVM
        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
        [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
        
        # Skip to Node.js installation section
        SKIP_NVM_INSTALL=true
    fi
else
    print_status "NVM not found. Proceeding with fresh installation..."
    SKIP_NVM_INSTALL=false
fi

# Update package index
print_status "Updating package index..."
sudo apt update

# Install required dependencies for NVM and Node.js compilation
print_status "Installing required dependencies..."
sudo apt install -y curl wget build-essential libssl-dev

# Install NVM (only if not skipping)
if [ "$SKIP_NVM_INSTALL" != true ]; then
    # Install NVM using the latest version from master branch (automatically gets the newest version)
    print_status "Installing NVM (latest version)..."

    # Download and install NVM from master branch - this automatically gets the latest version
    curl -o- "https://raw.githubusercontent.com/nvm-sh/nvm/master/install.sh" | bash

    # Export NVM directory and source NVM
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
    [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

    # Check if NVM was installed successfully
    if ! command_exists nvm; then
        # Try to source NVM manually
        if [ -s "$NVM_DIR/nvm.sh" ]; then
            source "$NVM_DIR/nvm.sh"
        else
            print_error "NVM installation failed. Please restart your terminal and run this script again."
            exit 1
        fi
    fi

    print_success "NVM installed successfully!"
else
    print_status "Using existing NVM installation..."
fi

# Install the latest LTS version of Node.js
print_status "Installing the latest LTS version of Node.js..."

# Check if Node.js LTS is already installed
if command_exists node; then
    CURRENT_NODE_VERSION=$(node --version)
    print_status "Current Node.js version: $CURRENT_NODE_VERSION"
    
    # Check if it's an LTS version
    CURRENT_LTS=$(nvm ls-remote --lts | tail -1 | awk '{print $1}' | sed 's/^v//')
    CURRENT_NODE_CLEAN=$(echo "$CURRENT_NODE_VERSION" | sed 's/^v//')
    
    if [ "$CURRENT_NODE_CLEAN" != "$CURRENT_LTS" ]; then
        if ask_confirmation "Do you want to install/update to the latest LTS version?"; then
            nvm install --lts
        else
            print_status "Keeping current Node.js version: $CURRENT_NODE_VERSION"
        fi
    else
        print_success "Latest LTS version is already installed: $CURRENT_NODE_VERSION"
    fi
else
    nvm install --lts
fi

# Use the LTS version
print_status "Setting LTS version as default..."
nvm use --lts
nvm alias default lts/*

# Install latest npm
print_status "Installing latest npm..."
nvm install-latest-npm

# Verify installation
print_status "Verifying installation..."
NODE_VERSION=$(node --version)
NPM_VERSION=$(npm --version)
NVM_VERSION_INSTALLED=$(nvm --version)

print_success "Installation completed successfully!"
echo
echo "=================================="
echo "Installation Summary:"
echo "=================================="
echo "NVM Version: $NVM_VERSION_INSTALLED"
echo "Node.js Version: $NODE_VERSION"
echo "npm Version: $NPM_VERSION"
echo "=================================="
echo

# Add instructions for shell configuration
print_warning "IMPORTANT: To use NVM in new terminal sessions, make sure these lines are in your shell profile:"
echo
echo "For bash (~/.bashrc) or zsh (~/.zshrc):"
echo 'export NVM_DIR="$HOME/.nvm"'
echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm'
echo '[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion'
echo

# Check if the lines are already in shell profiles
SHELL_PROFILE=""
if [ -n "$ZSH_VERSION" ]; then
    SHELL_PROFILE="$HOME/.zshrc"
elif [ -n "$BASH_VERSION" ]; then
    if [ -f "$HOME/.bashrc" ]; then
        SHELL_PROFILE="$HOME/.bashrc"
    elif [ -f "$HOME/.bash_profile" ]; then
        SHELL_PROFILE="$HOME/.bash_profile"
    fi
fi

if [ -n "$SHELL_PROFILE" ] && [ -f "$SHELL_PROFILE" ]; then
    if ! grep -q 'NVM_DIR.*nvm' "$SHELL_PROFILE"; then
        print_status "Adding NVM configuration to $SHELL_PROFILE..."
        echo "" >> "$SHELL_PROFILE"
        echo "# NVM Configuration" >> "$SHELL_PROFILE"
        echo 'export NVM_DIR="$HOME/.nvm"' >> "$SHELL_PROFILE"
        echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm' >> "$SHELL_PROFILE"
        echo '[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion' >> "$SHELL_PROFILE"
        print_success "NVM configuration added to $SHELL_PROFILE"
    else
        print_status "NVM configuration already exists in $SHELL_PROFILE"
    fi
fi

print_status "Useful NVM commands:"
echo "  nvm install node          # Install latest version"
echo "  nvm install --lts         # Install latest LTS version"
echo "  nvm install 18.17.0       # Install specific version"
echo "  nvm use node              # Use latest version"
echo "  nvm use --lts             # Use latest LTS version"
echo "  nvm use 18.17.0           # Use specific version"
echo "  nvm ls                    # List installed versions"
echo "  nvm ls-remote             # List available versions"
echo "  nvm current               # Show current version"
echo "  nvm alias default node    # Set default version"

print_success "Node.js and npm setup completed! Please restart your terminal or run 'source ~/.bashrc' (or ~/.zshrc) to start using Node.js."

# Display final summary
if [ "$SKIP_CONFIRMATION" = true ]; then
    print_status "Script completed in non-interactive mode (--yes flag used)"
fi
