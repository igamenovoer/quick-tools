#!/bin/bash

# `mkdir` command via docker, to gain privileges to create directories
# This script uses Docker (root in container) to create directories on host
# and sets ownership of newly created directories back to the current user.
# It supports standard mkdir options, including -p.

set -e

# Get current user info
CURRENT_UID=$(id -u)
CURRENT_GID=$(id -g)

# Check if Docker is available
if ! command -v docker &> /dev/null; then
    echo "Error: Docker is not installed or not in PATH" >&2
    exit 1
fi

# Function to find a suitable Ubuntu image (reuse pattern from other scripts)
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
    echo "Usage: $0 [--docker-image <image:tag>] [mkdir options] directory..."
    echo "Example: $0 -p /opt/my/app/data"
    echo "Example: $0 --docker-image ubuntu:22.04 -m 755 -p /var/lib/myapp/cache"
    echo ""
    echo "Options:"
    echo "  --docker-image <image:tag>  Specify Docker image to use"
    echo ""
    echo "Docker image priority:"
    echo "  1. --docker-image option"
    echo "  2. VIA_DOCKER_IMAGE environment variable"
    echo "  3. Local ubuntu:24.04/22.04/20.04 (in order)"
    echo ""
    echo "Notes:"
    echo "  - To support -p, the script mounts the deepest existing host parent,"
    echo "    then creates the remaining path inside the container."
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

# Separate mkdir options from directory operands; support "--" to end options
MKDIR_OPTIONS=()
DIRS=()
OPTIONS_DONE=0
for arg in "$@"; do
    if [ $OPTIONS_DONE -eq 0 ] && [ "$arg" = "--" ]; then
        OPTIONS_DONE=1
        continue
    fi
    if [ $OPTIONS_DONE -eq 0 ] && [[ "$arg" == -* ]]; then
        MKDIR_OPTIONS+=("$arg")
    else
        DIRS+=("$arg")
    fi
done

if [ ${#DIRS[@]} -eq 0 ]; then
    echo "Error: no directories specified" >&2
    usage
fi

# Detect presence of -p/--parents to decide mounting strategy
WITH_PARENTS=0
for opt in "${MKDIR_OPTIONS[@]}"; do
    if [ "$opt" = "-p" ] || [ "$opt" = "--parents" ]; then
        WITH_PARENTS=1
        break
    fi
done

# Determine Docker image to use
if [ -z "$DOCKER_IMAGE" ]; then
    if [ -n "$VIA_DOCKER_IMAGE" ]; then
        DOCKER_IMAGE="$VIA_DOCKER_IMAGE"
    else
        DOCKER_IMAGE=$(find_ubuntu_image)
    fi
fi

# Build mount list and container commands for each directory
MOUNT_DIRS=()
CONTAINER_CMDS=""
COUNTER=0

# Build a safely quoted string of mkdir options for inline command
MKDIR_OPTS_ESCAPED=""
for opt in "${MKDIR_OPTIONS[@]}"; do
    # Escape single quotes in options by closing/opening quotes safely
    esc=${opt//\'/\'"'"'\'}
    MKDIR_OPTS_ESCAPED+=" '$esc'"
done

for input_path in "${DIRS[@]}"; do
    # Resolve to absolute path (even if it doesn't exist yet)
    if [ -e "$input_path" ]; then
        ABS_PATH=$(realpath "$input_path")
    else
        ABS_PATH=$(realpath -m "$input_path" 2>/dev/null || echo "$input_path")
        if [[ ! "$ABS_PATH" = /* ]]; then
            ABS_PATH="$(pwd)/$input_path"
        fi
    fi

    if [ $WITH_PARENTS -eq 1 ]; then
        # Find the deepest existing ancestor on host
        MOUNT_PATH="$ABS_PATH"
        while [ ! -e "$MOUNT_PATH" ]; do
            MOUNT_PATH=$(dirname "$MOUNT_PATH")
        done
        # Determine the relative path to create inside container
        if [ "$ABS_PATH" = "$MOUNT_PATH" ]; then
            RELATIVE_PATH="."
        else
            RELATIVE_PATH="${ABS_PATH#"$MOUNT_PATH"/}"
        fi
    else
        # Without -p, parent must already exist
        PARENT_DIR=$(dirname "$ABS_PATH")
        if [ ! -d "$PARENT_DIR" ]; then
            echo "mkdir: cannot create directory '$ABS_PATH': No such file or directory" >&2
            exit 1
        fi
        MOUNT_PATH="$PARENT_DIR"
        RELATIVE_PATH="$(basename "$ABS_PATH")"
    fi

    CONTAINER_MOUNT="/mnt/path${COUNTER}"
    COUNTER=$((COUNTER + 1))

    # Mount ancestor with write permissions
    MOUNT_DIRS+=("-v" "$MOUNT_PATH:$CONTAINER_MOUNT:rw")

    # Escape relative path for safe insertion
    esc_rel=${RELATIVE_PATH//\'/\'"'"'\'}

    # For each target, check existence before, then mkdir, then chown only if newly created
    CONTAINER_CMDS+=$'\n'
    CONTAINER_CMDS+="TARGET=\"$CONTAINER_MOUNT/$esc_rel\"; \
if [ -e \"$CONTAINER_MOUNT/$esc_rel\" ]; then existed=1; else existed=0; fi; \
mkdir$MKDIR_OPTS_ESCAPED -- \"$CONTAINER_MOUNT/$esc_rel\"; \
if [ \$existed -eq 0 ]; then chown -R $CURRENT_UID:$CURRENT_GID \"$CONTAINER_MOUNT/$esc_rel\"; fi;"

done

# Run Docker container to perform the mkdir operations
# Root filesystem read-only; only our mounts are writable.
docker run --rm \
    --read-only \
    --tmpfs /tmp:rw,noexec,nosuid,size=10m \
    "${MOUNT_DIRS[@]}" \
    "$DOCKER_IMAGE" \
    bash -c "set -e;$CONTAINER_CMDS"
