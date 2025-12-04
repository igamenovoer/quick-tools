#!/bin/bash

# ==============================================================================
# getpack.bash
#
# A script to download .deb packages and their dependencies for offline
# installation.
#
# Usage:
#   ./getpack.bash <package1> [package2...] -o <directory> [--deps=all|append|none]
#
# ==============================================================================

# --- Function to display usage information ---
usage() {
    echo "Usage: $0 <package1> [package2...] [OPTIONS]"
    echo ""
    echo "Downloads specified apt packages and their dependencies to a directory."
    echo ""
    echo "Required Arguments:"
    echo "  <package>                  At least one package name to download."
    echo "  -o, --output <directory>   The directory to save the downloaded .deb files."
    echo ""
    echo "Options:"
    echo "  --deps=<mode>              Specify dependency handling mode. Default is 'all'."
    echo "                             all:    Download all recursive dependencies, assuming a clean system."
    echo "                             append: Download only dependencies not currently installed on this system."
    echo "                             none:   Download only the specified packages, no dependencies."
    echo "  -h, --help                 Display this help message."
    exit 1
}

# --- Initial default values ---
OUTPUT_DIR=""
DEPS_MODE="all"
PACKAGES=()

# --- Argument Parsing ---
# Loop through all arguments to separate packages from options.
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -o|--output)
            if [[ -n "$2" ]]; then
                OUTPUT_DIR="$2"
                shift # past argument
                shift # past value
            else
                echo "Error: --output requires a non-empty directory argument."
                exit 1
            fi
            ;;
        --deps=*)
            DEPS_MODE="${1#*=}"
            shift # past argument=value
            ;;
        -h|--help)
            usage
            ;;
        -*)
            echo "Unknown option: $1"
            usage
            ;;
        *)
            # If it's not an option, it's a package name
            PACKAGES+=("$1")
            shift # past argument
            ;;
    esac
done

# --- Validation Checks ---
# Check if an output directory was provided.
if [[ -z "$OUTPUT_DIR" ]]; then
    echo "Error: Output directory is required."
    usage
fi

# Check if at least one package was provided.
if [[ ${#PACKAGES[@]} -eq 0 ]]; then
    echo "Error: At least one package name is required."
    usage
fi

# Check if the deps mode is valid.
if [[ "$DEPS_MODE" != "all" && "$DEPS_MODE" != "append" && "$DEPS_MODE" != "none" ]]; then
    echo "Error: Invalid value for --deps. Must be 'all', 'append', or 'none'."
    usage
fi

# --- Main Logic ---
# Create the output directory if it doesn't exist.
echo "Creating output directory: $OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

# The command to get the dependency list.
# We always skip recommended and suggested packages for a minimal download.
DEPS_CMD="apt-cache depends --recurse --no-recommends --no-suggests --no-conflicts --no-breaks --no-replaces --no-enhances"

echo "Updating package list..."
sudo apt-get update > /dev/null

echo "Starting download process (Mode: $DEPS_MODE)..."

# Change to the output directory to download files there.
cd "$OUTPUT_DIR" || exit

case "$DEPS_MODE" in
    all)
        echo "Mode 'all': Downloading specified packages and all recursive dependencies."
        # Get the full recursive dependency list for all specified packages.
        # The 'grep' command filters the output to only include package names.
        PACKAGE_LIST=$($DEPS_CMD "${PACKAGES[@]}" | grep "^\w")
        echo "Found $(echo "$PACKAGE_LIST" | wc -l) packages to download."
        apt-get download $PACKAGE_LIST
        ;;

    append)
        echo "Mode 'append': Downloading packages and dependencies not currently installed."
        # Get the full list of dependencies needed.
        FULL_DEPS=$($DEPS_CMD "${PACKAGES[@]}" | grep "^\w")
        # Get the list of all currently installed packages.
        INSTALLED_PKGS=$(dpkg-query -W -f='${Package}\n')

        # Find which packages from the full dependency list are NOT in the installed list.
        # This gives us the list of missing dependencies.
        # We also add the user-specified packages themselves to ensure they are downloaded.
        PACKAGES_TO_DOWNLOAD=$(comm -23 <(echo "$FULL_DEPS" | sort) <(echo "$INSTALLED_PKGS" | sort))
        
        # Combine the missing dependencies with the packages the user explicitly asked for.
        FINAL_LIST=$(echo -e "${PACKAGES[@]}\n$PACKAGES_TO_DOWNLOAD" | sort -u)

        echo "Found $(echo "$FINAL_LIST" | wc -l) packages to download."
        apt-get download $FINAL_LIST
        ;;

    none)
        echo "Mode 'none': Downloading only the specified packages."
        apt-get download "${PACKAGES[@]}"
        ;;
esac

echo ""
echo "Download complete."
echo "Files are located in: $(pwd)"
echo "To install offline, copy this directory to the target machine, cd into it, and run: sudo dpkg -i *.deb"

