#!/bin/bash

set -e

# --- Configuration ---
MOUNT_POINT="/mnt/ramdisk"
SIZE="16G"
REMOVE=0

# Parse command-line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --size)
            SIZE="$2"
            # Convert GB/MB to G/M for tmpfs
            SIZE=${SIZE//GB/G}
            SIZE=${SIZE//MB/M}
            SIZE=${SIZE//gb/G}
            SIZE=${SIZE//mb/M}
            shift
            ;;
        --remove)
            REMOVE=1
            ;;
        *)
            echo "Unknown parameter passed: $1"
            echo "Usage: $0 [--size <size>] [--remove]"
            exit 1
            ;;
    esac
    shift
done

# ---

# Ensure sudo is available and usable before proceeding
if ! command -v sudo >/dev/null 2>&1; then
    echo "This script requires sudo, but it was not found in PATH."
    exit 1
fi

if ! sudo -v; then
    echo "Unable to acquire sudo privileges. Exiting."
    exit 1
fi

if [[ ${REMOVE} -eq 1 ]]; then
    echo "This script will remove the ramdisk at ${MOUNT_POINT}."
    read -p "Proceed with removal? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 1
    fi

    if mountpoint -q "${MOUNT_POINT}"; then
        echo "Unmounting ${MOUNT_POINT}..."
        sudo umount "${MOUNT_POINT}"
    else
        echo "${MOUNT_POINT} is not currently mounted."
    fi

    if sudo grep -qE "^[^#]*[[:space:]]${MOUNT_POINT}[[:space:]]" /etc/fstab; then
        echo "Removing /etc/fstab entry for ${MOUNT_POINT}."
        sudo sed -i "\|^[^#]*[[:space:]]${MOUNT_POINT}[[:space:]]|d" /etc/fstab
    else
        echo "No /etc/fstab entry found for ${MOUNT_POINT}."
    fi

    if [[ -d ${MOUNT_POINT} ]]; then
        echo "Removing directory ${MOUNT_POINT}."
        sudo rmdir "${MOUNT_POINT}" 2>/dev/null || sudo rm -rf "${MOUNT_POINT}"
    fi

    echo "Ramdisk removal completed."
    exit 0
fi

# Get current user's UID and GID
USER_ID=$(id -u)
GROUP_ID=$(id -g)

echo "This script will create a ${SIZE} ramdisk at ${MOUNT_POINT}."
read -p "You will need sudo privileges. Do you want to continue? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

echo "Creating mount point: ${MOUNT_POINT}"
sudo mkdir -p "${MOUNT_POINT}"

if mountpoint -q "${MOUNT_POINT}"; then
    echo "Existing ramdisk detected. Unmounting ${MOUNT_POINT}..."
    sudo umount "${MOUNT_POINT}"
fi

FSTAB_LINE="tmpfs ${MOUNT_POINT} tmpfs rw,size=${SIZE},uid=${USER_ID},gid=${GROUP_ID},mode=0755 0 0"

if sudo grep -qE "^[^#]*[[:space:]]${MOUNT_POINT}[[:space:]]" /etc/fstab; then
    echo "Updating existing /etc/fstab entry for ${MOUNT_POINT}."
    sudo sed -i "s|^[^#]*[[:space:]]${MOUNT_POINT}[[:space:]].*|${FSTAB_LINE}|" /etc/fstab
else
    echo "Adding the following line to /etc/fstab:"
    echo "  ${FSTAB_LINE}"
    echo "${FSTAB_LINE}" | sudo tee -a /etc/fstab >/dev/null
fi

echo "Mounting the ramdisk..."
sudo mount "${MOUNT_POINT}"

echo "Setting ownership of ${MOUNT_POINT} to user ${USER_ID}..."
sudo chown "${USER_ID}:${GROUP_ID}" "${MOUNT_POINT}"

echo "Ramdisk created and mounted successfully at ${MOUNT_POINT}."
echo "You can now use it for your temporary files."
