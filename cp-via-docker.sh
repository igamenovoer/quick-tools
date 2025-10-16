#!/bin/bash

# `cp` command via docker, to gain privileges to read/write files
# This script uses Docker to copy files with root privileges
# and then sets ownership back to the current user

set -e

# Get current user info
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
    echo "Usage: $0 [--docker-image <image:tag>] [cp options] source destination"
    echo "Example: $0 -r /path/to/source /path/to/dest"
    echo "Example: $0 --docker-image ubuntu:22.04 -r /path/to/source /path/to/dest"
    echo ""
    echo "Options:"
    echo "  --docker-image <image:tag>  Specify Docker image to use"
    echo ""
    echo "Docker image priority:"
    echo "  1. --docker-image option"
    echo "  2. VIA_DOCKER_IMAGE environment variable"
    echo "  3. Local ubuntu:24.04/22.04/20.04 (in order)"
    echo ""
    echo "This script copies files using Docker as root and sets ownership to current user."
    exit 1
}

# Parse docker image option
DOCKER_IMAGE=""
if [ $# -ge 2 ] && [ "$1" = "--docker-image" ]; then
    DOCKER_IMAGE="$2"
    shift 2
fi

# Check arguments
if [ $# -lt 2 ]; then
    usage
fi

# Parse arguments - separate cp options from source and destination
CP_OPTIONS=()
ARGS=()

for arg in "$@"; do
    ARGS+=("$arg")
done

# Last two non-option arguments should be source and destination
# Find source and destination (last two arguments)
SRC="${ARGS[-2]}"
DST="${ARGS[-1]}"

# All arguments except last two are cp options
CP_OPTIONS=("${ARGS[@]:0:$((${#ARGS[@]}-2))}")

# Convert to absolute paths
SRC=$(realpath "$SRC" 2>/dev/null || echo "$SRC")
DST=$(realpath -m "$DST" 2>/dev/null || echo "$DST")

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

# Determine mount points
# We need to mount parent directories to handle cases where dst doesn't exist yet
SRC_DIR=$(dirname "$SRC")
SRC_NAME=$(basename "$SRC")
DST_DIR=$(dirname "$DST")
DST_NAME=$(basename "$DST")

# Create destination directory if it doesn't exist (on host)
mkdir -p "$DST_DIR" 2>/dev/null || true

# Mount points in container
CONTAINER_SRC_DIR="/mnt/src"
CONTAINER_DST_DIR="/mnt/dst"

# Run Docker container to perform the copy
# IMPORTANT: Source is mounted as :ro (read-only) to prevent any modifications
# Container is automatically removed after execution (--rm flag)
docker run --rm \
    --read-only \
    --tmpfs /tmp:rw,noexec,nosuid,size=100m \
    -v "$SRC_DIR:$CONTAINER_SRC_DIR:ro" \
    -v "$DST_DIR:$CONTAINER_DST_DIR:rw" \
    "$DOCKER_IMAGE" \
    bash -c "
        set -e
        # Perform the copy operation (source is read-only mounted, cannot be modified)
        cp ${CP_OPTIONS[*]} \"$CONTAINER_SRC_DIR/$SRC_NAME\" \"$CONTAINER_DST_DIR/$DST_NAME\"
        
        # Change ownership recursively to match the host user
        if [ -d \"$CONTAINER_DST_DIR/$DST_NAME\" ]; then
            chown -R $CURRENT_UID:$CURRENT_GID \"$CONTAINER_DST_DIR/$DST_NAME\"
        else
            chown $CURRENT_UID:$CURRENT_GID \"$CONTAINER_DST_DIR/$DST_NAME\"
        fi
    "