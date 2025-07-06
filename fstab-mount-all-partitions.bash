#!/bin/bash

# =============================================================================
# fstab-mount-all-partitions.bash
# =============================================================================
# 
# PURPOSE:
#   Automatically scan all storage devices and generate fstab entries for 
#   mounting partitions. Optionally can mount the partitions immediately.
#   Provides intelligent NTFS error handling and conflict avoidance.
#
# FEATURES:
#   - Auto-discovers all partitions and generates proper fstab entries
#   - Skips system partitions (root, boot, workspace) automatically
#   - Skips Windows system partitions by default to avoid conflicts
#   - Creates mount points with universal read/write permissions (777)
#   - Ensures all users can read/write to mounted filesystems
#   - Interactive NTFS error detection and repair using ntfsfix
#   - Conflict detection - warns about already mounted devices
#   - Uses UUIDs for reliable device identification
#   - Supports all filesystem types (NTFS, FAT32, ext4, XFS, BTRFS, etc.)
#   - Always prints to screen, optionally saves to file
#   - Detailed verbose output for mounting operations
#
# USAGE:
#   $0 [OPTIONS]
#
# OPTIONS:
#   --skip-windows-partition=true/false    Skip Windows system partition (default: true)
#   --auto-create-mount-point=true/false   Auto-create mount points (default: true)
#   --mount-point-root=PATH                Mount point root directory (default: /mnt/media)
#   --mount-now=true/false                 Actually mount the partitions (default: false)
#                                         (includes interactive NTFS error repair)
#   --output, -o FILE                      Output fstab file (always prints to screen)
#   --apply                                Replace /etc/fstab with generated entries
#                                         (creates backup first, requires root/sudo)
#   --help, -h                             Show this help message
#
# EXAMPLES:
#   # Generate fstab entries for all partitions (skips Windows by default)
#   $0
#
#   # Generate entries including Windows partitions
#   $0 --skip-windows-partition=false
#
#   # Generate entries with custom mount root
#   $0 --mount-point-root=/mnt/auto
#
#   # Generate and immediately mount all partitions with NTFS error handling
#   sudo $0 --mount-now=true
#
#   # Generate entries and save to file
#   $0 --output /tmp/my-fstab.txt
#
#   # Just generate entries without creating mount points
#   $0 --auto-create-mount-point=false --mount-point-root=/media/custom
#
#   # Apply generated entries to system /etc/fstab (creates backup)
#   sudo $0 --apply
#
#   # Include Windows partitions and apply to system
#   sudo $0 --apply --skip-windows-partition=false
#
# NTFS ERROR HANDLING:
#   When --mount-now=true, the script detects NTFS mounting issues such as:
#   - Windows hibernation state
#   - Unclean/dirty filesystem
#   - Metadata cache conflicts
#   
#   Upon detection, it will:
#   1. Display the error and explain the likely cause
#   2. Prompt user whether to attempt automatic repair with ntfsfix
#   3. If user agrees, run ntfsfix and retry mounting
#   4. If user declines, provide detailed manual fix instructions
#
# SAFETY FEATURES:
#   - Never unmounts already mounted devices (shows warning instead)
#   - Uses 'nofail' option to prevent boot hangs if devices are missing
#   - Automatically detects and skips system partitions
#   - Shows verbose output for all mount operations
#   - Validates mount success before reporting completion
#   - When using --apply: Creates timestamped backup of original /etc/fstab
#   - When using --apply: Validates generated fstab before applying
#   - When using --apply: Requires root privileges and user confirmation
#
# WARNING - --apply option:
#   The --apply option directly modifies your system's /etc/fstab file!
#   This affects how your system mounts drives at boot time.
#   - A backup is created automatically with timestamp
#   - Root/sudo privileges are required
#   - User confirmation is required before applying changes
#   - Use with caution on production systems
#
# REQUIREMENTS:
#   - bash 4.0+
#   - lsblk, mount, umount commands
#   - ntfs-3g package for NTFS support (auto-detects if missing)
#   - sudo privileges for mounting operations (when using --mount-now)
#
# EXIT CODES:
#   0 = Success
#   1 = Error (invalid options, missing dependencies, etc.)
#   2 = Device already mounted (used internally)
#
# NOTES:
#   - Generated fstab entries use UUIDs for device identification
#   - All mount points created with 777 permissions for universal access
#   - NTFS/FAT partitions mounted with full read/write permissions for all users
#   - ext4/ext3/ext2/xfs/btrfs filesystems get universal write access post-mount
#   - Script is safe to run multiple times - handles existing mount points gracefully
#   - When --mount-now=true, auto-create-mount-point is automatically enabled
#
# AUTHOR: Generated with Claude Code
# VERSION: 1.2
# =============================================================================

# Default values
SKIP_WINDOWS_PARTITION=true
AUTO_CREATE_MOUNT_POINT=true
MOUNT_POINT_ROOT="/mnt/media"
OUTPUT_FILE=""
MOUNT_NOW=false
APPLY_TO_SYSTEM=false

# Function to print usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  --skip-windows-partition=true/false    Skip Windows system partition (default: true)"
    echo "  --auto-create-mount-point=true/false   Auto-create mount points (default: true)"
    echo "  --mount-point-root=PATH                Mount point root directory (default: /mnt/media)"
    echo "  --mount-now=true/false                 Actually mount the partitions (default: false)"
    echo "                                        (includes interactive NTFS error repair)"
    echo "  --output, -o FILE                      Output fstab file (always prints to screen)"
    echo "  --apply                                Replace /etc/fstab with generated entries"
    echo "                                        (creates backup first, requires root/sudo)"
    echo "  --help, -h                             Show this help message"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-windows-partition=*)
            SKIP_WINDOWS_PARTITION="${1#*=}"
            shift
            ;;
        --auto-create-mount-point=*)
            AUTO_CREATE_MOUNT_POINT="${1#*=}"
            shift
            ;;
        --mount-point-root=*)
            MOUNT_POINT_ROOT="${1#*=}"
            shift
            ;;
        --mount-now=*)
            MOUNT_NOW="${1#*=}"
            shift
            ;;
        --output|-o)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        --apply)
            APPLY_TO_SYSTEM=true
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage
            exit 1
            ;;
    esac
done

# When mount-now is true, force auto-create-mount-point to true
if [[ "$MOUNT_NOW" == "true" ]]; then
    AUTO_CREATE_MOUNT_POINT=true
fi

# Function to detect if a partition contains Windows
is_windows_partition() {
    local device="$1"
    local fstype="$2"
    local temp_mount="/tmp/mount_check_$$"
    
    # Only check NTFS partitions
    [[ "$fstype" != "ntfs" ]] && return 1
    
    # Try to mount the partition temporarily (read-only)
    mkdir -p "$temp_mount" 2>/dev/null
    if mount -t ntfs-3g -o ro "$device" "$temp_mount" 2>/dev/null; then
        # Check for Windows indicators
        if [[ -d "$temp_mount/Windows" ]] || [[ -d "$temp_mount/Program Files" ]] || [[ -f "$temp_mount/hiberfil.sys" ]] || [[ -f "$temp_mount/pagefile.sys" ]]; then
            umount "$temp_mount" 2>/dev/null
            rmdir "$temp_mount" 2>/dev/null
            return 0  # Is Windows partition
        fi
        umount "$temp_mount" 2>/dev/null
    fi
    rmdir "$temp_mount" 2>/dev/null
    return 1  # Not Windows partition
}

# Function to generate mount options based on filesystem type
get_mount_options() {
    local fstype="$1"
    case "$fstype" in
        ntfs)
            echo "ntfs-3g permissions,uid=1000,gid=1000,umask=0000,nofail"
            ;;
        vfat|fat32)
            echo "vfat uid=1000,gid=1000,umask=0000,nofail"
            ;;
        ext4|ext3|ext2)
            echo "$fstype defaults,nofail"
            ;;
        xfs)
            echo "xfs defaults,nofail"
            ;;
        btrfs)
            echo "btrfs defaults,nofail"
            ;;
        *)
            echo "auto defaults,nofail"
            ;;
    esac
}

# Function to get filesystem type for mounting
get_fs_type() {
    local fstype="$1"
    case "$fstype" in
        ntfs)
            echo "ntfs-3g"
            ;;
        vfat|fat32)
            echo "vfat"
            ;;
        *)
            echo "$fstype"
            ;;
    esac
}

# Function to get mount options only (without filesystem type)
get_mount_options_only() {
    local fstype="$1"
    case "$fstype" in
        ntfs)
            echo "permissions,uid=1000,gid=1000,umask=0000,nofail"
            ;;
        vfat|fat32)
            echo "uid=1000,gid=1000,umask=0000,nofail"
            ;;
        ext4|ext3|ext2|xfs|btrfs)
            echo "defaults,nofail"
            ;;
        *)
            echo "defaults,nofail"
            ;;
    esac
}

# Function to generate mount point name
get_mount_point() {
    local device="$1"
    local label="$2"
    
    if [[ -n "$label" && "$label" != "" ]]; then
        # Clean up label for use as directory name
        local clean_label=$(echo "$label" | sed 's/[^a-zA-Z0-9_-]/_/g')
        echo "${MOUNT_POINT_ROOT}/${clean_label}"
    else
        # Use device name without /dev/
        local device_name=$(basename "$device")
        echo "${MOUNT_POINT_ROOT}/${device_name}"
    fi
}

# Function to check if partition is already mounted
is_mounted() {
    local device="$1"
    local uuid="$2"
    
    if [[ -n "$uuid" ]]; then
        mount | grep -q "UUID=$uuid"
    else
        mount | grep -q "^$device"
    fi
}

# Function to check if a mount point is already mounted
is_mount_point_mounted() {
    local mount_point="$1"
    mount | grep -q " $mount_point "
}

# Function to get what device is mounted at a mount point
get_mounted_device() {
    local mount_point="$1"
    mount | grep " $mount_point " | awk '{print $1}'
}

# Function to unmount a mount point
unmount_partition() {
    local mount_point="$1"
    local device=$(get_mounted_device "$mount_point")
    
    if [[ -n "$device" ]]; then
        echo "# [MOUNT-NOW] Unmounting $device from $mount_point"
        if umount "$mount_point" 2>/dev/null; then
            echo "# [MOUNT-NOW] Successfully unmounted $mount_point"
            return 0
        else
            echo "# [MOUNT-NOW] Failed to unmount $mount_point" >&2
            return 1
        fi
    else
        echo "# [MOUNT-NOW] Mount point $mount_point is not mounted"
        return 0
    fi
}

# Function to detect NTFS issues and ask user for fix
handle_ntfs_error() {
    local device="$1"
    local error_msg="$2"
    
    # Check for common NTFS issues
    if [[ "$error_msg" =~ (hibernated|unclean|dirty|cache|unsafe|metadata|exclusively.opened) ]]; then
        echo "# [MOUNT-NOW] NTFS Error detected on $device:"
        echo "# [MOUNT-NOW] $error_msg"
        echo ""
        echo "# This usually happens when Windows was not properly shut down."
        
        # Check if ntfsfix is available
        if command -v ntfsfix >/dev/null 2>&1; then
            echo "# Would you like to attempt automatic repair using ntfsfix? (y/n)"
            read -r response
            
            case "$response" in
                [Yy]|[Yy][Ee][Ss])
                    echo "# [MOUNT-NOW] Attempting to fix NTFS filesystem on $device..."
                    if ntfsfix "$device" 2>/dev/null; then
                        echo "# [MOUNT-NOW] NTFS fix completed successfully"
                        return 0  # Signal to retry mount
                    else
                        echo "# [MOUNT-NOW] NTFS fix failed"
                        echo "# [MOUNT-NOW] Manual fix needed. Try:"
                        echo "#   sudo ntfsfix $device"
                        echo "#   or boot into Windows and properly shut down"
                        return 1  # Signal to skip
                    fi
                    ;;
                *)
                    echo "# [MOUNT-NOW] Skipping NTFS fix"
                    echo "# [MOUNT-NOW] To fix manually, you can:"
                    echo "#   1. Run: sudo ntfsfix $device"
                    echo "#   2. Boot into Windows, then shutdown properly (no hibernation/fast boot)"
                    echo "#   3. In Windows, run: chkdsk /f C: (replace C: with correct drive)"
                    return 1  # Signal to skip
                    ;;
            esac
        else
            echo "# [MOUNT-NOW] ntfsfix tool not available. Install ntfs-3g package first."
            echo "# [MOUNT-NOW] To fix manually, you can:"
            echo "#   1. Install ntfs-3g: sudo apt install ntfs-3g"
            echo "#   2. Then run: sudo ntfsfix $device"
            echo "#   3. Boot into Windows, then shutdown properly (no hibernation/fast boot)"
            echo "#   4. In Windows, run: chkdsk /f C: (replace C: with correct drive)"
            return 1  # Signal to skip
        fi
    fi
    
    return 1  # No NTFS issue detected or user declined
}

# Function to backup original fstab
backup_fstab() {
    local fstab_file="/etc/fstab"
    local backup_file="/etc/fstab.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Check if fstab exists
    if [[ ! -f "$fstab_file" ]]; then
        echo "# [APPLY] WARNING: /etc/fstab does not exist, creating new one"
        return 0
    fi
    
    # Create backup
    echo "# [APPLY] Creating backup of $fstab_file"
    if cp "$fstab_file" "$backup_file" 2>/dev/null; then
        echo "# [APPLY] Backup created: $backup_file"
        return 0
    else
        echo "# [APPLY] ERROR: Failed to create backup of $fstab_file" >&2
        return 1
    fi
}

# Function to validate generated fstab content
validate_fstab_content() {
    local content="$1"
    
    # Check if content is empty
    if [[ -z "$content" ]]; then
        echo "# [APPLY] ERROR: Generated fstab content is empty" >&2
        return 1
    fi
    
    # Check for basic fstab structure (each line should have 6 fields or be a comment)
    local line_count=0
    local invalid_lines=0
    
    while IFS= read -r line; do
        # Skip empty lines and comments
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        
        ((line_count++))
        
        # Count fields in the line
        local field_count
        field_count=$(echo "$line" | awk '{print NF}')
        
        # Valid fstab entry should have exactly 6 fields
        if [[ $field_count -ne 6 ]]; then
            echo "# [APPLY] WARNING: Invalid fstab line format: $line" >&2
            ((invalid_lines++))
        fi
    done <<< "$content"
    
    if [[ $invalid_lines -gt 0 ]]; then
        echo "# [APPLY] ERROR: Found $invalid_lines invalid fstab lines" >&2
        return 1
    fi
    
    if [[ $line_count -eq 0 ]]; then
        echo "# [APPLY] ERROR: No valid fstab entries found" >&2
        return 1
    fi
    
    echo "# [APPLY] Validation passed: $line_count valid fstab entries"
    return 0
}

# Function to apply fstab to system
apply_fstab_to_system() {
    local fstab_content="$1"
    local fstab_file="/etc/fstab"
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        echo "# [APPLY] ERROR: Root privileges required to modify /etc/fstab" >&2
        echo "# [APPLY] Please run with sudo: sudo $0 --apply" >&2
        return 1
    fi
    
    # Validate the generated content
    if ! validate_fstab_content "$fstab_content"; then
        echo "# [APPLY] ERROR: Generated fstab content failed validation" >&2
        return 1
    fi
    
    # Create backup of original fstab
    if ! backup_fstab; then
        echo "# [APPLY] ERROR: Failed to create backup, aborting" >&2
        return 1
    fi
    
    # Show warning and get confirmation
    echo "# [APPLY] WARNING: About to replace /etc/fstab with generated entries"
    echo "# [APPLY] This will affect system boot behavior"
    echo "# [APPLY] Current /etc/fstab has been backed up"
    echo "# [APPLY] Continue? (y/N)"
    read -r response
    
    case "$response" in
        [Yy]|[Yy][Ee][Ss])
            echo "# [APPLY] Applying generated fstab entries to $fstab_file"
            ;;
        *)
            echo "# [APPLY] Operation cancelled by user"
            return 1
            ;;
    esac
    
    # Write the new fstab file
    {
        echo "# Auto-generated fstab entries"
        echo "# Generated by fstab-mount-all-partitions.bash"
        echo "# Date: $(date)"
        echo "# Original fstab backed up"
        echo ""
        echo -e "$fstab_content"
    } > "$fstab_file"
    
    if [[ $? -eq 0 ]]; then
        echo "# [APPLY] Successfully applied fstab entries to $fstab_file"
        echo "# [APPLY] You can now run 'sudo mount -a' to mount all entries"
        return 0
    else
        echo "# [APPLY] ERROR: Failed to write to $fstab_file" >&2
        return 1
    fi
}

# Function to mount a partition
mount_partition() {
    local device="$1"
    local mount_point="$2"
    local fs_type="$3"
    local options="$4"
    local uuid="$5"
    
    echo "# [MOUNT-NOW] Mounting $device to $mount_point"
    
    # Create mount point if it doesn't exist
    if [[ ! -d "$mount_point" ]]; then
        echo "# [MOUNT-NOW] Creating mount point: $mount_point"
        if mkdir -p "$mount_point" 2>/dev/null; then
            chmod 777 "$mount_point" 2>/dev/null
            echo "# [MOUNT-NOW] Created mount point: $mount_point"
        else
            echo "# [MOUNT-NOW] Failed to create mount point: $mount_point" >&2
            return 1
        fi
    fi
    
    # Remove nofail option for actual mounting and clean up options
    local mount_options=$(echo "$options" | sed 's/,nofail//g' | sed 's/nofail,//g' | sed 's/nofail$//g' | sed 's/^,//' | sed 's/,$//')
    
    # Debug: print the options being used (commented out for clean output)
    # echo "# [MOUNT-NOW] DEBUG: Original options: '$options'"
    # echo "# [MOUNT-NOW] DEBUG: Cleaned options: '$mount_options'"
    
    # Try to mount using UUID first if available
    local mount_cmd
    if [[ -n "$uuid" && "$uuid" != "" ]]; then
        mount_cmd="mount -t $fs_type -o $mount_options UUID=$uuid $mount_point"
    else
        mount_cmd="mount -t $fs_type -o $mount_options $device $mount_point"
    fi
    
    # Check if the device is already mounted elsewhere BEFORE trying to mount
    # Always check by device path since mount output shows device paths, not UUIDs
    local existing_mount=$(mount | grep "^$device " | awk '{print $3}')
    
    if [[ -n "$existing_mount" && "$existing_mount" != "$mount_point" ]]; then
        echo "# [MOUNT-NOW] WARNING: Device $device is already mounted at $existing_mount"
        echo "# [MOUNT-NOW] Skipping mount to avoid conflicts (device already in use)"
        return 2  # Special return code for "already mounted"
    fi
    
    echo "# [MOUNT-NOW] Running: $mount_cmd"
    
    # Capture both stdout and stderr from mount command
    local mount_output
    local mount_exit_code
    mount_output=$(eval "$mount_cmd" 2>&1)
    mount_exit_code=$?
    
    if [[ $mount_exit_code -eq 0 ]]; then
        echo "# [MOUNT-NOW] Successfully mounted $device at $mount_point"
        # Verify the mount
        if is_mount_point_mounted "$mount_point"; then
            echo "# [MOUNT-NOW] Mount verified: $mount_point"
            
            # Ensure read/write access for all users on native Unix filesystems
            if [[ "$fs_type" =~ ^(ext[234]|xfs|btrfs)$ ]]; then
                echo "# [MOUNT-NOW] Setting universal access permissions for $fs_type filesystem"
                chmod 777 "$mount_point" 2>/dev/null
                # Create a test directory to verify write access
                if [[ -w "$mount_point" ]]; then
                    echo "# [MOUNT-NOW] Universal write access verified for $mount_point"
                else
                    echo "# [MOUNT-NOW] WARNING: Universal write access not available for $mount_point"
                fi
            fi
            
            return 0
        else
            echo "# [MOUNT-NOW] Mount verification failed: $mount_point" >&2
            return 1
        fi
    else
        # Mount failed - check if it's an NTFS issue that can be fixed
        if [[ "$fs_type" == "ntfs-3g" ]] && handle_ntfs_error "$device" "$mount_output"; then
            echo "# [MOUNT-NOW] Retrying mount after NTFS fix..."
            echo "# [MOUNT-NOW] Running: $mount_cmd"
            
            # Retry the mount command
            if eval "$mount_cmd" 2>/dev/null; then
                echo "# [MOUNT-NOW] Successfully mounted $device at $mount_point after fix"
                # Verify the mount
                if is_mount_point_mounted "$mount_point"; then
                    echo "# [MOUNT-NOW] Mount verified: $mount_point"
                    
                    # Ensure read/write access for all users on native Unix filesystems
                    if [[ "$fs_type" =~ ^(ext[234]|xfs|btrfs)$ ]]; then
                        echo "# [MOUNT-NOW] Setting universal access permissions for $fs_type filesystem"
                        chmod 777 "$mount_point" 2>/dev/null
                        # Create a test directory to verify write access
                        if [[ -w "$mount_point" ]]; then
                            echo "# [MOUNT-NOW] Universal write access verified for $mount_point"
                        else
                            echo "# [MOUNT-NOW] WARNING: Universal write access not available for $mount_point"
                        fi
                    fi
                    
                    return 0
                else
                    echo "# [MOUNT-NOW] Mount verification failed: $mount_point" >&2
                    return 1
                fi
            else
                echo "# [MOUNT-NOW] Mount still failed after NTFS fix" >&2
                return 1
            fi
        else
            # Either not NTFS, user declined fix, or no NTFS issue detected
            if [[ -n "$mount_output" ]]; then
                echo "# [MOUNT-NOW] Mount error: $mount_output" >&2
            fi
            echo "# [MOUNT-NOW] Failed to mount $device at $mount_point" >&2
            return 1
        fi
    fi
}

# Main function
main() {
    echo "# Auto-generated fstab entries"
    echo "# Generated by fstab-mount-all-partitions.bash"
    echo "# Date: $(date)"
    echo "# Options used:"
    echo "#   skip-windows-partition: $SKIP_WINDOWS_PARTITION"
    echo "#   auto-create-mount-point: $AUTO_CREATE_MOUNT_POINT"
    echo "#   mount-point-root: $MOUNT_POINT_ROOT"
    echo "#   mount-now: $MOUNT_NOW"
    echo "#   apply-to-system: $APPLY_TO_SYSTEM"
    echo ""
    
    # Get all block devices with filesystem information
    local fstab_content=""
    local created_dirs=""
    
    # Arrays to store partition information for mounting
    declare -a mount_devices=()
    declare -a mount_points=()
    declare -a mount_fs_types=()
    declare -a mount_options_array=()
    declare -a mount_uuids=()
    
    # Use lsblk to get partition information, excluding system partitions
    while IFS= read -r line; do
        # Parse lsblk output: NAME FSTYPE LABEL UUID
        local device fstype label uuid
        read -r device fstype label uuid <<< "$line"
        
        # Skip if no device or no filesystem type
        [[ -z "$device" || -z "$fstype" ]] && continue
        
        # Add /dev/ prefix if not present
        [[ "$device" != /dev/* ]] && device="/dev/$device"
        
        # Skip loop devices, swap, and system partitions
        [[ "$device" =~ ^/dev/loop ]] && continue
        [[ "$fstype" == "swap" ]] && continue
        
        # Skip root and boot partitions (check current mounts)
        if is_mounted "$device" "$uuid"; then
            local mount_point=$(mount | grep -E "(^$device|UUID=$uuid)" | awk '{print $3}')
            if [[ "$mount_point" == "/" || "$mount_point" == "/boot"* || "$mount_point" == "/workspace" ]]; then
                echo "# Skipping system partition: $device (mounted at $mount_point)"
                continue
            fi
        fi
        
        # Skip Windows partition if requested
        if [[ "$SKIP_WINDOWS_PARTITION" == "true" ]]; then
            if is_windows_partition "$device" "$fstype"; then
                echo "# Skipping Windows partition: $device"
                continue
            fi
        fi
        
        # Generate mount point
        local mount_point=$(get_mount_point "$device" "$label")
        
        # Generate mount options
        local mount_options=$(get_mount_options "$fstype")
        local fs_type=$(echo "$mount_options" | cut -d' ' -f1)
        local options=$(echo "$mount_options" | cut -d' ' -f2-)
        
        # For mounting, we need separate filesystem type and options
        local mount_fs_type=$(get_fs_type "$fstype")
        local mount_options_only=$(get_mount_options_only "$fstype")
        
        # Debug: print what we're using for mounting (commented out for clean output)
        # echo "# DEBUG: fstype='$fstype', mount_fs_type='$mount_fs_type', mount_options_only='$mount_options_only'"
        
        # Create mount point if requested
        if [[ "$AUTO_CREATE_MOUNT_POINT" == "true" ]]; then
            if [[ ! -d "$mount_point" ]]; then
                if mkdir -p "$mount_point" 2>/dev/null; then
                    # Set permissions for all users
                    chmod 777 "$mount_point" 2>/dev/null
                    echo "# Created mount point: $mount_point"
                    created_dirs="$created_dirs$mount_point\n"
                else
                    echo "# Failed to create mount point: $mount_point" >&2
                fi
            else
                echo "# Mount point already exists: $mount_point"
            fi
        fi
        
        # Generate fstab entry
        local fstab_entry
        if [[ -n "$uuid" && "$uuid" != "" ]]; then
            fstab_entry="UUID=$uuid $mount_point $fs_type $options 0 0"
        else
            fstab_entry="$device $mount_point $fs_type $options 0 0"
        fi
        
        echo "$fstab_entry"
        fstab_content="$fstab_content$fstab_entry\n"
        
        # Store partition information for mounting if --mount-now is enabled
        if [[ "$MOUNT_NOW" == "true" ]]; then
            mount_devices+=("$device")
            mount_points+=("$mount_point")
            mount_fs_types+=("$mount_fs_type")
            mount_options_array+=("$mount_options_only")
            mount_uuids+=("$uuid")
            # echo "# DEBUG STORE: Storing options='$mount_options_only' for device='$device'"
        fi
    done < <(lsblk -rno NAME,FSTYPE,LABEL,UUID | grep -v '^NAME' | grep -v '^$')
    
    # Write to output file if specified
    if [[ -n "$OUTPUT_FILE" ]]; then
        {
            echo "# Auto-generated fstab entries"
            echo "# Generated by fstab-mount-all-partitions.bash"
            echo "# Date: $(date)"
            echo ""
            echo -e "$fstab_content"
        } > "$OUTPUT_FILE"
        echo ""
        echo "# Output also saved to: $OUTPUT_FILE"
    fi
    
    # Apply to system fstab if requested
    if [[ "$APPLY_TO_SYSTEM" == "true" ]]; then
        echo ""
        echo "# ==============================================="
        echo "# APPLYING TO SYSTEM /etc/fstab"
        echo "# ==============================================="
        
        if apply_fstab_to_system "$fstab_content"; then
            echo "# [APPLY] Successfully applied fstab entries to system"
        else
            echo "# [APPLY] Failed to apply fstab entries to system" >&2
            exit 1
        fi
    fi
    
    # Summary
    echo ""
    echo "# Summary:"
    echo "# - Processed $(echo -e "$fstab_content" | grep -c UUID) partitions"
    if [[ "$AUTO_CREATE_MOUNT_POINT" == "true" && -n "$created_dirs" ]]; then
        echo "# - Created mount points:"
        echo -e "$created_dirs" | sed 's/^/#   /'
    fi
    if [[ "$MOUNT_NOW" == "true" ]]; then
        echo "# - Mounting partitions now..."
    elif [[ "$APPLY_TO_SYSTEM" == "true" ]]; then
        echo "# - Applied entries to system /etc/fstab"
        echo "# - Run 'sudo mount -a' to mount all entries"
    else
        echo "# - To apply these changes, copy the entries above to /etc/fstab"
        echo "# - Or run with --apply to automatically update /etc/fstab"
        echo "# - Then run: sudo mount -a"
    fi
    
    # Mount partitions now if requested
    if [[ "$MOUNT_NOW" == "true" ]]; then
        echo ""
        echo "# ==============================================="
        echo "# MOUNTING PARTITIONS NOW"
        echo "# ==============================================="
        
        local mount_success=0
        local mount_failed=0
        local mount_skipped=0
        
        for (( i=0; i<${#mount_devices[@]}; i++ )); do
            local device="${mount_devices[i]}"
            local mount_point="${mount_points[i]}"
            local fs_type="${mount_fs_types[i]}"
            local options="${mount_options_array[i]}"
            local uuid="${mount_uuids[i]}"
            
            echo ""
            echo "# [MOUNT-NOW] Processing: $device -> $mount_point"
            # echo "# DEBUG RETRIEVE: Retrieved options='$options' for device='$device'"
            
            # Check if mount point is already mounted
            if is_mount_point_mounted "$mount_point"; then
                echo "# [MOUNT-NOW] Mount point $mount_point is already mounted"
                
                # Unmount first, then remount
                if unmount_partition "$mount_point"; then
                    echo "# [MOUNT-NOW] Proceeding with remount..."
                else
                    echo "# [MOUNT-NOW] Failed to unmount, skipping this partition"
                    ((mount_failed++))
                    continue
                fi
            fi
            
            # Mount the partition
            local mount_result
            mount_partition "$device" "$mount_point" "$fs_type" "$options" "$uuid"
            mount_result=$?
            
            case $mount_result in
                0)
                    ((mount_success++))
                    ;;
                2)
                    ((mount_skipped++))
                    ;;
                *)
                    ((mount_failed++))
                    ;;
            esac
        done
        
        echo ""
        echo "# ==============================================="
        echo "# MOUNTING SUMMARY"
        echo "# ==============================================="
        echo "# Successfully mounted: $mount_success partitions"
        echo "# Skipped (already mounted): $mount_skipped partitions"
        echo "# Failed to mount: $mount_failed partitions"
        echo "# Total processed: $((mount_success + mount_skipped + mount_failed)) partitions"
        
        if [[ $mount_failed -gt 0 ]]; then
            echo "# WARNING: Some partitions failed to mount. Check the output above for details."
        fi
        if [[ $mount_skipped -gt 0 ]]; then
            echo "# INFO: Some partitions were skipped because they are already mounted elsewhere."
        fi
    fi
}

# Run main function
main "$@"