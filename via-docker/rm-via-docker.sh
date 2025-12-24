#!/bin/bash

# `rm` command via docker, to gain privileges to remove files/directories
# This script uses Docker (root in container) to remove host files/directories

set -e

# Check if Docker is available
if ! command -v docker &> /dev/null; then
    echo "Error: Docker is not installed or not in PATH" >&2
    exit 1
fi

# Function to find a suitable Ubuntu image
find_ubuntu_image() {
    for version in "24.04" "22.04" "20.04"; do
        if docker images --format "{{.Repository}}:{{.Tag}}" | grep -q "^ubuntu:${version}$"; then
            echo "ubuntu:${version}"
            return 0
        fi
    done

    if docker images --format "{{.Repository}}:{{.Tag}}" | grep -q "^ubuntu:latest$"; then
        echo "ubuntu:latest"
        return 0
    fi

    echo "ubuntu:20.04"
    return 0
}

usage() {
    echo "Usage: $0 [--docker-image <image:tag>] [rm options] file..." >&2
    echo "Example: $0 -f /path/to/file" >&2
    echo "Example: $0 -rf /path/to/dir" >&2
    echo "Example: $0 --docker-image ubuntu:22.04 -rf -- /path/starting-with-dash" >&2
    echo "" >&2
    echo "Options:" >&2
    echo "  --docker-image <image:tag>  Specify Docker image to use" >&2
    echo "" >&2
    echo "Docker image priority:" >&2
    echo "  1. --docker-image option" >&2
    echo "  2. VIA_DOCKER_IMAGE environment variable" >&2
    echo "  3. Local ubuntu:24.04/22.04/20.04 (in order)" >&2
    exit 1
}

# Parse docker image option
DOCKER_IMAGE=""
if [ $# -ge 2 ] && [ "$1" = "--docker-image" ]; then
    DOCKER_IMAGE="$2"
    shift 2
fi

# Require at least one argument after optional image selection
if [ $# -eq 0 ]; then
    usage
fi

# Separate rm options from operands; support "--" to end options
RM_OPTIONS=()
TARGETS=()
OPTIONS_DONE=0
for arg in "$@"; do
    if [ $OPTIONS_DONE -eq 0 ] && [ "$arg" = "--" ]; then
        OPTIONS_DONE=1
        continue
    fi
    if [ $OPTIONS_DONE -eq 0 ] && [[ "$arg" == -* ]]; then
        RM_OPTIONS+=("$arg")
    else
        TARGETS+=("$arg")
    fi
done

if [ ${#TARGETS[@]} -eq 0 ]; then
    echo "Error: no files specified" >&2
    usage
fi

# Determine Docker image to use
if [ -z "$DOCKER_IMAGE" ]; then
    if [ -n "$VIA_DOCKER_IMAGE" ]; then
        DOCKER_IMAGE="$VIA_DOCKER_IMAGE"
    else
        DOCKER_IMAGE=$(find_ubuntu_image)
    fi
fi

# Convert all target paths to absolute paths and prepare mounts
MOUNT_DIRS=()
CONTAINER_PATHS=()
declare -A MOUNT_MAP
MOUNT_COUNTER=0

for target in "${TARGETS[@]}"; do
    # Convert to absolute path
    if [ -e "$target" ] || [ -L "$target" ]; then
        ABS_PATH=$(realpath "$target" 2>/dev/null || echo "$target")
    else
        ABS_PATH=$(realpath -m "$target" 2>/dev/null || echo "$target")
        if [[ ! "$ABS_PATH" = /* ]]; then
            ABS_PATH="$(pwd)/$target"
        fi
    fi

    # Special-case root to avoid dirname/basename oddities
    if [ "$ABS_PATH" = "/" ]; then
        MOUNT_PATH="/"
        RELATIVE_PATH=""
    else
        # To remove a path, we need write access to its parent directory.
        # Mount the deepest existing ancestor of the parent dir.
        PARENT_DIR=$(dirname "$ABS_PATH")
        MOUNT_PATH="$PARENT_DIR"
        while [ ! -e "$MOUNT_PATH" ]; do
            MOUNT_PATH=$(dirname "$MOUNT_PATH")
        done

        if [ "$MOUNT_PATH" = "/" ]; then
            RELATIVE_PATH="${ABS_PATH#/}"
        else
            RELATIVE_PATH="${ABS_PATH#"$MOUNT_PATH"/}"
        fi
    fi

    # Register mount path if new
    if [ -z "${MOUNT_MAP[$MOUNT_PATH]}" ]; then
        CONTAINER_MOUNT="/mnt/path${MOUNT_COUNTER}"
        MOUNT_COUNTER=$((MOUNT_COUNTER + 1))
        MOUNT_MAP["$MOUNT_PATH"]="$CONTAINER_MOUNT"
        MOUNT_DIRS+=("-v" "$MOUNT_PATH:$CONTAINER_MOUNT:rw")
    else
        CONTAINER_MOUNT="${MOUNT_MAP[$MOUNT_PATH]}"
    fi

    if [ -z "$RELATIVE_PATH" ]; then
        CONTAINER_PATHS+=("$CONTAINER_MOUNT")
    else
        CONTAINER_PATHS+=("$CONTAINER_MOUNT/$RELATIVE_PATH")
    fi
done

# Run Docker container to perform the rm
# Root filesystem read-only; only our mounts are writable.
docker run --rm \
    --read-only \
    --tmpfs /tmp:rw,noexec,nosuid,size=10m \
    "${MOUNT_DIRS[@]}" \
    "$DOCKER_IMAGE" \
    rm "${RM_OPTIONS[@]}" -- "${CONTAINER_PATHS[@]}"
