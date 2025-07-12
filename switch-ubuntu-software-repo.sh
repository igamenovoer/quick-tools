#!/bin/bash

# switch-ubuntu-software-repo.sh
# Script to switch Ubuntu repository sources between official and Chinese mirrors
# Supports Ubuntu >=18.04, all architectures, and future DEB822 format

set -euo pipefail

# Global variables
SOURCES_FILE=""
BACKUP_DIR="/etc/apt/sources.backup"
UBUNTU_VERSION=""
ARCHITECTURE=""
USE_PORTS="false"
USE_DEB822="false"
DRY_RUN="false"
MIRROR_NAME=""
OUTPUT_FILE=""

show_usage() {
    cat << EOF
Usage: $0 [options] <mirror_name>

Available mirrors:
  official  - Official Ubuntu repositories
  tuna      - Tsinghua University (mirrors.tuna.tsinghua.edu.cn)
  aliyun    - Alibaba Cloud (mirrors.aliyun.com)
  163       - NetEase (mirrors.163.com) 
  ustc      - University of Science and Technology of China (mirrors.ustc.edu.cn)
  cn        - China Archive (cn.archive.ubuntu.com)

Options:
  --dry-run            Show what changes would be made without modifying the system
  --output/-o <file>   Export new repository configuration to specified file

Supported:
  - Ubuntu versions: 18.04, 20.04, 22.04, 24.04+ 
  - Architectures: x86_64/amd64, ARM64, armhf, ppc64el, s390x, riscv64
  - Repository formats: Traditional sources.list and DEB822 .sources

Example:
  $0 tuna                          # Switch to Tsinghua mirror
  $0 --dry-run tuna                # Show what would change with Tsinghua mirror
  $0 --output new-sources.list tuna # Export Tsinghua config to file
  $0 -o new-sources.sources tuna   # Same as above (short form)
  $0 --dry-run -o file.sources tuna # Show changes AND export to file
  $0 official                      # Switch back to official repositories
EOF
}

detect_system() {
    # Detect Ubuntu version
    if [[ -f /etc/os-release ]]; then
        UBUNTU_VERSION=$(grep '^VERSION_ID=' /etc/os-release | cut -d'"' -f2)
    else
        echo "Error: Cannot detect Ubuntu version" >&2
        exit 1
    fi
    
    # Detect architecture
    ARCHITECTURE=$(dpkg --print-architecture)
    
    # Determine if we need to use ports.ubuntu.com
    case "$ARCHITECTURE" in
        "amd64"|"i386")
            USE_PORTS="false"
            ;;
        "arm64"|"armhf"|"armel"|"ppc64el"|"s390x"|"riscv64")
            USE_PORTS="true"
            ;;
        *)
            echo "Warning: Unknown architecture $ARCHITECTURE, assuming ports repository" >&2
            USE_PORTS="true"
            ;;
    esac
    
    # Determine repository format and file location
    if [[ -f "/etc/apt/sources.list.d/ubuntu.sources" ]]; then
        # Ubuntu 24.04+ with DEB822 format
        USE_DEB822="true"
        SOURCES_FILE="/etc/apt/sources.list.d/ubuntu.sources"
    elif [[ -f "/etc/apt/sources.list" ]]; then
        # Ubuntu 18.04-22.04 with traditional format
        USE_DEB822="false"
        SOURCES_FILE="/etc/apt/sources.list"
    else
        echo "Error: No Ubuntu sources file found" >&2
        exit 1
    fi
    
    echo "Detected: Ubuntu $UBUNTU_VERSION, $ARCHITECTURE architecture"
    echo "Using: $(basename "$SOURCES_FILE") ($([ "$USE_DEB822" = "true" ] && echo "DEB822" || echo "traditional") format)"
    if [[ "$USE_PORTS" = "true" ]]; then
        echo "Architecture requires ubuntu-ports repositories"
    fi
}

check_root() {
    if [[ $EUID -ne 0 ]] && [[ "$DRY_RUN" = "false" ]] && [[ -z "$OUTPUT_FILE" ]]; then
        echo "Error: This script must be run as root (use sudo)" >&2
        echo "Note: Use --dry-run or --output to preview/export changes without root privileges" >&2
        exit 1
    fi
}

backup_sources() {
    local backup_file="${BACKUP_DIR}-$(date +%Y%m%d-%H%M%S)"
    if [[ "$DRY_RUN" = "true" ]] && [[ -z "$OUTPUT_FILE" ]]; then
        echo "[DRY RUN] Would create backup of current $(basename "$SOURCES_FILE") at: $backup_file"
    elif [[ -n "$OUTPUT_FILE" ]]; then
        echo "[OUTPUT MODE] Skipping backup - no system files will be modified"
    elif [[ "$DRY_RUN" = "false" ]]; then
        echo "Creating backup of current $(basename "$SOURCES_FILE")..."
        cp "$SOURCES_FILE" "$backup_file"
        echo "Backup created at $backup_file"
    fi
}

show_diff() {
    local temp_file="$1"
    local file_type="$2"
    
    echo ""
    echo "========================================"
    echo "Changes that would be made to $file_type:"
    echo "========================================"
    
    if command -v diff >/dev/null 2>&1; then
        echo "--- Current $(basename "$SOURCES_FILE")"
        echo "+++ New $(basename "$SOURCES_FILE")"
        diff -u "$SOURCES_FILE" "$temp_file" || true
    else
        echo "BEFORE:"
        echo "-------"
        cat "$SOURCES_FILE"
        echo ""
        echo "AFTER:"
        echo "------"
        cat "$temp_file"
    fi
    
    echo ""
    echo "File location: $SOURCES_FILE"
    echo "Repository format: $file_type"
}

generate_comment_header() {
    local mirror_name="$1"
    local mirror_url="$2"
    local current_time=$(date '+%Y-%m-%d %H:%M:%S %Z')
    local file_type="$([ "$USE_DEB822" = "true" ] && echo "DEB822" || echo "traditional")"
    local target_file="$([ "$USE_DEB822" = "true" ] && echo "ubuntu.sources" || echo "sources.list")"
    
    cat << 'EOF'
# Ubuntu Repository Configuration - Generated by switch-ubuntu-software-repo.sh
EOF
    echo "# Generated on: $current_time"
    cat << 'EOF'
# 
# System Information:
EOF
    echo "#   Ubuntu Version: $UBUNTU_VERSION"
    echo "#   Architecture: $ARCHITECTURE"
    echo "#   Repository Format: $file_type"
    echo "#   Uses Ubuntu Ports: $([ "$USE_PORTS" = "true" ] && echo "Yes" || echo "No")"
    cat << 'EOF'
#
# Mirror Information:
EOF
    echo "#   Mirror Name: $mirror_name"
    echo "#   Mirror URL: $mirror_url"
    echo "#   Repository Type: $([ "$USE_PORTS" = "true" ] && echo "ubuntu-ports" || echo "ubuntu")"
    cat << 'EOF'
#
# How to Apply This Configuration:
#
# IMPORTANT: Always backup your current configuration first!
#
# 1. Backup current configuration:
EOF
    echo "#    sudo cp $SOURCES_FILE $SOURCES_FILE.backup-\$(date +%Y%m%d-%H%M%S)"
    cat << 'EOF'
#
# 2. Apply this configuration:
EOF
    echo "#    sudo cp $(basename "$OUTPUT_FILE") $SOURCES_FILE"
    cat << 'EOF'
#
# 3. Update package lists:
#    sudo apt update
#
# 4. To revert changes (if needed):
EOF
    echo "#    sudo cp $SOURCES_FILE.backup-* $SOURCES_FILE"
    cat << 'EOF'
#    sudo apt update
#
# Alternative method using this script:
EOF
    echo "#   sudo ./switch-ubuntu-software-repo.sh $mirror_name"
    cat << 'EOF'
#
EOF
    echo "# File will be installed to: $SOURCES_FILE"
    echo "# Target filename: $target_file"
    cat << 'EOF'
#
# ================================================================

EOF
}

get_mirror_urls() {
    local mirror_name="$1"
    local archive_url=""
    local ports_url=""
    
    case "$mirror_name" in
        "official")
            archive_url="archive.ubuntu.com"
            ports_url="ports.ubuntu.com"
            ;;
        "tuna")
            archive_url="mirrors.tuna.tsinghua.edu.cn"
            ports_url="mirrors.tuna.tsinghua.edu.cn"
            ;;
        "aliyun")
            archive_url="mirrors.aliyun.com"
            ports_url="mirrors.aliyun.com"
            ;;
        "163")
            archive_url="mirrors.163.com"
            ports_url="mirrors.163.com"
            ;;
        "ustc")
            archive_url="mirrors.ustc.edu.cn"
            ports_url="mirrors.ustc.edu.cn"
            ;;
        "cn")
            archive_url="cn.archive.ubuntu.com"
            ports_url="ports.ubuntu.com"  # cn mirror doesn't have ports
            ;;
        *)
            return 1
            ;;
    esac
    
    if [[ "$USE_PORTS" = "true" ]]; then
        echo "$ports_url"
    else
        echo "$archive_url"
    fi
}

switch_mirror_traditional() {
    local mirror_name="$1"
    local mirror_url="$2"
    local temp_file
    temp_file=$(mktemp)
    
    if [[ "$DRY_RUN" = "true" ]]; then
        echo "[DRY RUN] Would switch to $mirror_name mirror ($mirror_url) in traditional format..."
    else
        echo "Switching to $mirror_name mirror ($mirror_url) in traditional format..."
    fi
    
    if [[ "$USE_PORTS" = "true" ]]; then
        # For ARM64 and other port architectures, replace ports URLs and add ubuntu-ports path
        sed -e "s|archive\.ubuntu\.com/ubuntu|$mirror_url/ubuntu-ports|g" \
            -e "s|security\.ubuntu\.com/ubuntu|$mirror_url/ubuntu-ports|g" \
            -e "s|ports\.ubuntu\.com/ubuntu-ports|$mirror_url/ubuntu-ports|g" \
            -e "s|ports\.ubuntu\.com|$mirror_url|g" \
            "$SOURCES_FILE" > "$temp_file"
    else
        # For x86_64/amd64, use standard ubuntu repositories
        sed -e "s|archive\.ubuntu\.com|$mirror_url|g" \
            -e "s|security\.ubuntu\.com|$mirror_url|g" \
            -e "s|ports\.ubuntu\.com|$mirror_url|g" \
            "$SOURCES_FILE" > "$temp_file"
    fi
    
    validate_and_apply_changes "$temp_file" "^deb"
}

switch_mirror_deb822() {
    local mirror_name="$1"
    local mirror_url="$2"
    local temp_file
    temp_file=$(mktemp)
    
    if [[ "$DRY_RUN" = "true" ]]; then
        echo "[DRY RUN] Would switch to $mirror_name mirror ($mirror_url) in DEB822 format..."
    else
        echo "Switching to $mirror_name mirror ($mirror_url) in DEB822 format..."
    fi
    
    if [[ "$USE_PORTS" = "true" ]]; then
        # For ARM64 and other port architectures, update URIs to use ubuntu-ports
        sed -e "s|URIs: http://[^/]*/ubuntu|URIs: http://$mirror_url/ubuntu-ports|g" \
            -e "s|URIs: https://[^/]*/ubuntu|URIs: https://$mirror_url/ubuntu-ports|g" \
            -e "s|URIs: http://[^/]*/ubuntu-ports|URIs: http://$mirror_url/ubuntu-ports|g" \
            -e "s|URIs: https://[^/]*/ubuntu-ports|URIs: https://$mirror_url/ubuntu-ports|g" \
            "$SOURCES_FILE" > "$temp_file"
    else
        # For x86_64/amd64, use standard ubuntu repositories  
        sed -e "s|URIs: http://[^/]*/ubuntu|URIs: http://$mirror_url/ubuntu|g" \
            -e "s|URIs: https://[^/]*/ubuntu|URIs: https://$mirror_url/ubuntu|g" \
            -e "s|URIs: http://[^/]*/ubuntu-ports|URIs: http://$mirror_url/ubuntu|g" \
            -e "s|URIs: https://[^/]*/ubuntu-ports|URIs: https://$mirror_url/ubuntu|g" \
            "$SOURCES_FILE" > "$temp_file"
    fi
    
    validate_and_apply_changes "$temp_file" "^Types:"
}

validate_and_apply_changes() {
    local temp_file="$1"
    local validation_pattern="$2"
    local file_type="$([ "$USE_DEB822" = "true" ] && echo "DEB822" || echo "traditional")"
    
    # Verify the temp file is not empty and has valid content
    if [[ ! -s "$temp_file" ]] || ! grep -q "$validation_pattern" "$temp_file"; then
        echo "Error: Generated repository file appears to be invalid" >&2
        rm -f "$temp_file"
        exit 1
    fi
    
    # Handle output to file
    if [[ -n "$OUTPUT_FILE" ]]; then
        echo "Exporting repository configuration to: $OUTPUT_FILE"
        
        # Create output file with comment header + content
        generate_comment_header "$MIRROR_NAME" "$(get_mirror_urls "$MIRROR_NAME")" > "$OUTPUT_FILE"
        cat "$temp_file" >> "$OUTPUT_FILE"
        
        echo "Repository configuration exported successfully"
        echo "File format: $file_type"
        echo "To apply: sudo cp $(basename "$OUTPUT_FILE") $SOURCES_FILE && sudo apt update"
        
        # If also dry-run, show the diff
        if [[ "$DRY_RUN" = "true" ]]; then
            echo ""
            show_diff "$temp_file" "$file_type"
        fi
    fi
    
    # Handle dry-run (only if not doing output-only)
    if [[ "$DRY_RUN" = "true" ]] && [[ -z "$OUTPUT_FILE" ]]; then
        show_diff "$temp_file" "$file_type"
        echo ""
        echo "[DRY RUN] Would update package lists with: apt update"
    fi
    
    # Handle actual application (only if not dry-run and not output-only)
    if [[ "$DRY_RUN" = "false" ]] && [[ -z "$OUTPUT_FILE" ]]; then
        # Move temp file to target location
        mv "$temp_file" "$SOURCES_FILE"
        
        echo "Successfully switched repository sources"
        echo "Updating package lists..."
        apt update
    fi
    
    # Clean up temp file if not moved
    if [[ "$DRY_RUN" = "true" ]] || [[ -n "$OUTPUT_FILE" ]]; then
        rm -f "$temp_file"
    fi
}

switch_mirror() {
    local mirror_name="$1"
    local mirror_url="$2"
    
    if [[ "$USE_DEB822" = "true" ]]; then
        switch_mirror_deb822 "$mirror_name" "$mirror_url"
    else
        switch_mirror_traditional "$mirror_name" "$mirror_url"
    fi
}

parse_arguments() {
    # Parse arguments and set global variables
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN="true"
                shift
                ;;
            --output|-o)
                if [[ $# -gt 1 ]] && [[ ! "$2" =~ ^- ]]; then
                    OUTPUT_FILE="$2"
                    shift 2
                else
                    echo "Error: --output/-o requires a filename" >&2
                    show_usage
                    exit 1
                fi
                ;;
            -*)
                echo "Error: Unknown option $1" >&2
                show_usage
                exit 1
                ;;
            *)
                if [[ -z "$MIRROR_NAME" ]]; then
                    MIRROR_NAME="$1"
                else
                    echo "Error: Multiple mirror names specified" >&2
                    show_usage
                    exit 1
                fi
                shift
                ;;
        esac
    done
    
    if [[ -z "$MIRROR_NAME" ]]; then
        echo "Error: Mirror name is required" >&2
        show_usage
        exit 1
    fi
}

main() {
    # Parse arguments first to set DRY_RUN and MIRROR_NAME variables
    parse_arguments "$@"
    
    check_root
    detect_system
    
    # Validate mirror name and get URL
    local mirror_url
    if ! mirror_url=$(get_mirror_urls "$MIRROR_NAME"); then
        echo "Error: Unknown mirror '$MIRROR_NAME'" >&2
        echo ""
        show_usage
        exit 1
    fi
    
    # Check if sources file exists
    if [[ ! -f "$SOURCES_FILE" ]]; then
        echo "Error: $SOURCES_FILE not found" >&2
        exit 1
    fi
    
    backup_sources
    switch_mirror "$MIRROR_NAME" "$mirror_url"
    
    echo ""
    if [[ -n "$OUTPUT_FILE" ]]; then
        # Output mode - final summary already handled in validate_and_apply_changes
        if [[ "$DRY_RUN" = "true" ]]; then
            echo "[DRY RUN + OUTPUT] Configuration exported and preview shown"
        fi
    elif [[ "$DRY_RUN" = "true" ]]; then
        echo "[DRY RUN] Would have switched repository sources to $MIRROR_NAME ($mirror_url)"
        if [[ "$USE_PORTS" = "true" ]]; then
            echo "[DRY RUN] Would use ubuntu-ports repository for $ARCHITECTURE architecture"
        fi
        echo "Run without --dry-run to apply these changes."
    else
        echo "Repository sources successfully switched to $MIRROR_NAME ($mirror_url)"
        if [[ "$USE_PORTS" = "true" ]]; then
            echo "Using ubuntu-ports repository for $ARCHITECTURE architecture"
        fi
        echo "You can now install packages using the new mirror."
    fi
}

main "$@"