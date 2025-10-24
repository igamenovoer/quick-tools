#!/bin/bash

# `chmod` command via docker, to gain privileges to change file permissions
# This script uses Docker to change file permissions with root privileges

set -e

# Get current user info (not strictly needed for chmod but kept for consistency)
CURRENT_UID=$(id -u)
CURRENT_GID=$(id -g)

# Check if Docker is available
if ! command -v docker &> /dev/null; then
    echo "Error: Docker is not installed or not in PATH" >&2
    exit 1
fi

# Function to find a suitable Ubuntu image
find_ubuntu_image() {
    # Check for ubuntu images in order of preference
    for version in "24.04" "22.04" "20.04"; do
        if docker images --format "{{.Repository}}:{{.Tag}}" | grep -q "^ubuntu:${version}$"; then
            echo "ubuntu:${version}"
            return 0
        fi
    done
    
    # If no specific version found, check for ubuntu:latest
    if docker images --format "{{.Repository}}:{{.Tag}}" | grep -q "^ubuntu:latest$"; then
        echo "ubuntu:latest"
        return 0
    fi
    
    # Default to ubuntu:20.04 (will be pulled if not available)
    echo "ubuntu:20.04"
    return 0
}

# Usage function
usage() {
    echo "Usage: $0 [--docker-image <image:tag>] [chmod options] mode file..."
    echo "Example: $0 755 /path/to/file"
    echo "Example: $0 -R 755 /path/to/directory"
    echo "Example: $0 --docker-image ubuntu:22.04 u+x /path/to/script.sh"
    echo ""
    echo "Options:"
    echo "  --docker-image <image:tag>  Specify Docker image to use"
    echo ""
    echo "Docker image priority:"
    echo "  1. --docker-image option"
    echo "  2. VIA_DOCKER_IMAGE environment variable"
    echo "  3. Local ubuntu:24.04/22.04/20.04 (in order)"
    echo ""
    echo "This script changes file permissions using Docker as root."
    exit 1
}

# Parse docker image option
DOCKER_IMAGE=""
if [ $# -ge 2 ] && [ "$1" = "--docker-image" ]; then
    DOCKER_IMAGE="$2"
    shift 2
fi

# Check arguments - need at least mode and one file
if [ $# -lt 2 ]; then
    usage
fi

# Parse arguments - separate chmod options from mode and files
CHMOD_OPTIONS=()
MODE=""
FILES=()
MODE_FOUND=0

for arg in "$@"; do
    if [ $MODE_FOUND -eq 0 ]; then
        # Before we find the mode, collect options
        if [[ "$arg" == -* ]]; then
            CHMOD_OPTIONS+=("$arg")
        else
            # First non-option argument is the mode
            MODE="$arg"
            MODE_FOUND=1
        fi
    else
        # After mode, everything is a file path
        FILES+=("$arg")
    fi
done

# Validate we have mode and files
if [ -z "$MODE" ] || [ ${#FILES[@]} -eq 0 ]; then
    echo "Error: chmod requires a mode and at least one file" >&2
    usage
fi

# Convert all file paths to absolute paths and prepare mounts
MOUNT_DIRS=()
CONTAINER_PATHS=()
declare -A MOUNT_MAP
MOUNT_COUNTER=0

for file_path in "${FILES[@]}"; do
    # Convert to absolute path
    if [ -e "$file_path" ]; then
        ABS_PATH=$(realpath "$file_path")
    else
        # Path doesn't exist, try to resolve it anyway
        ABS_PATH=$(realpath -m "$file_path" 2>/dev/null || echo "$file_path")
        if [[ ! "$ABS_PATH" = /* ]]; then
            ABS_PATH="$(pwd)/$file_path"
        fi
    fi
    
    # For chmod, we need the item itself or its parent if it doesn't exist
    if [ -e "$ABS_PATH" ]; then
        MOUNT_PATH="$ABS_PATH"
        RELATIVE_PATH=""
    else
        MOUNT_PATH=$(dirname "$ABS_PATH")
        RELATIVE_PATH=$(basename "$ABS_PATH")
    fi
    
    # Check if we already have this mount path
    if [ -z "${MOUNT_MAP[$MOUNT_PATH]}" ]; then
        CONTAINER_PATH="/mnt/path${MOUNT_COUNTER}"
        MOUNT_COUNTER=$((MOUNT_COUNTER + 1))
        MOUNT_MAP["$MOUNT_PATH"]="$CONTAINER_PATH"
        MOUNT_DIRS+=("-v" "$MOUNT_PATH:$CONTAINER_PATH:rw")
    else
        CONTAINER_PATH="${MOUNT_MAP[$MOUNT_PATH]}"
    fi
    
    # Build the path to pass to chmod inside container
    if [ -z "$RELATIVE_PATH" ]; then
        CONTAINER_PATHS+=("$CONTAINER_PATH")
    else
        CONTAINER_PATHS+=("$CONTAINER_PATH/$RELATIVE_PATH")
    fi
done

# Determine Docker image to use
if [ -z "$DOCKER_IMAGE" ]; then
    # Check environment variable
    if [ -n "$VIA_DOCKER_IMAGE" ]; then
        DOCKER_IMAGE="$VIA_DOCKER_IMAGE"
    else
        # Find a suitable Ubuntu image from local images
        DOCKER_IMAGE=$(find_ubuntu_image)
    fi
fi

# Build chmod command arguments safely
CHMOD_CMD="chmod"
for opt in "${CHMOD_OPTIONS[@]}"; do
    CHMOD_CMD+=" '$opt'"
done
CHMOD_CMD+=" '$MODE'"
for cpath in "${CONTAINER_PATHS[@]}"; do
    CHMOD_CMD+=" '$cpath'"
done

# Run Docker container to perform the chmod
# Container is automatically removed after execution (--rm flag)
docker run --rm \
    --read-only \
    --tmpfs /tmp:rw,noexec,nosuid,size=10m \
    "${MOUNT_DIRS[@]}" \
    "$DOCKER_IMAGE" \
    bash -c "set -e; $CHMOD_CMD"
