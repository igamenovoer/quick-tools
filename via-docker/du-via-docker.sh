#!/bin/bash

# `du` command via docker, to gain privileges to read files/directories
# This script uses Docker to estimate file space usage with root privileges

set -e

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
    echo "Usage: $0 [--docker-image <image:tag>] [du options] [path...]"
    echo "Example: $0 -sh /path/to/directory"
    echo "Example: $0 --docker-image ubuntu:22.04 -h --max-depth=1 /var/log"
    echo ""
    echo "Options:"
    echo "  --docker-image <image:tag>  Specify Docker image to use"
    echo ""
    echo "Docker image priority:"
    echo "  1. --docker-image option"
    echo "  2. VIA_DOCKER_IMAGE environment variable"
    echo "  3. Local ubuntu:24.04/22.04/20.04 (in order)"
    echo ""
    echo "This script runs du using Docker as root to inspect restricted paths."
    exit 1
}

# Parse docker image option
DOCKER_IMAGE=""
if [ $# -ge 2 ] && [ "$1" = "--docker-image" ]; then
    DOCKER_IMAGE="$2"
    shift 2
fi

# Show help if explicitly requested
if [ $# -ge 1 ] && { [ "$1" = "-h" ] || [ "$1" = "--help" ]; }; then
    usage
fi

# Parse arguments - separate du options from paths
DU_OPTIONS=()
PATHS=()
MOUNT_DIRS=()
CONTAINER_PATHS=()
OPTIONS_DONE=0

for arg in "$@"; do
    if [ $OPTIONS_DONE -eq 0 ] && [ "$arg" = "--" ]; then
        OPTIONS_DONE=1
        DU_OPTIONS+=("--")
        continue
    fi

    if [ $OPTIONS_DONE -eq 0 ] && [[ "$arg" == -* ]]; then
        DU_OPTIONS+=("$arg")
    else
        PATHS+=("$arg")
    fi
done

# If no paths specified, use current directory
if [ ${#PATHS[@]} -eq 0 ]; then
    PATHS=(".")
fi

# Process each path
declare -A MOUNT_MAP
MOUNT_COUNTER=0

for path in "${PATHS[@]}"; do
    # Convert to absolute path
    if [ -e "$path" ] || [ -L "$path" ]; then
        ABS_PATH=$(realpath "$path" 2>/dev/null || echo "$path")
    else
        ABS_PATH=$(realpath -m "$path" 2>/dev/null || echo "$path")
        if [[ ! "$ABS_PATH" = /* ]]; then
            ABS_PATH="$(pwd)/$path"
        fi
    fi

    # Determine what to mount (the path itself if it exists, or its parent)
    if [ -e "$ABS_PATH" ] || [ -L "$ABS_PATH" ]; then
        MOUNT_PATH="$ABS_PATH"
        RELATIVE_PATH=""
    else
        MOUNT_PATH=$(dirname "$ABS_PATH")
        RELATIVE_PATH=$(basename "$ABS_PATH")
    fi

    # Reuse mounts for shared paths
    if [ -z "${MOUNT_MAP[$MOUNT_PATH]}" ]; then
        CONTAINER_PATH="/mnt/path${MOUNT_COUNTER}"
        MOUNT_COUNTER=$((MOUNT_COUNTER + 1))
        MOUNT_MAP["$MOUNT_PATH"]="$CONTAINER_PATH"
        MOUNT_DIRS+=("-v" "$MOUNT_PATH:$CONTAINER_PATH:ro")
    else
        CONTAINER_PATH="${MOUNT_MAP[$MOUNT_PATH]}"
    fi

    # Build the path to pass to du inside container
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

# Run Docker container to perform the du
# Container is automatically removed after execution (--rm flag)
docker run --rm \
    --read-only \
    --tmpfs /tmp:rw,noexec,nosuid,size=10m \
    "${MOUNT_DIRS[@]}" \
    "$DOCKER_IMAGE" \
    du "${DU_OPTIONS[@]}" "${CONTAINER_PATHS[@]}"
