#!/bin/bash

# Script to upload files to remote SSH hosts with progress display
# Usage: ./upload-file.sh [ssh-host-name|user@host] [file-to-upload] [remote-path] [--pw password]

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored messages
print_info() {
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

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [SSH_HOST] [FILE_TO_UPLOAD] [REMOTE_PATH] [OPTIONS]

Arguments:
  SSH_HOST         SSH host from config (e.g., L20-hz) or user@host format
  FILE_TO_UPLOAD   Local file or directory to upload
  REMOTE_PATH      Destination path on remote host

Options:
  --pw PASSWORD    SSH password (optional, uses sshpass)

Examples:
  $0 L20-hz /path/to/file.txt /remote/path/
  $0 user@192.168.1.100 /path/to/dir /remote/path/ --pw mypassword
  $0 L20-hz ./myfile.tar.gz /home/user/backups/

EOF
    exit 1
}

# Parse arguments
if [ $# -lt 3 ]; then
    print_error "Insufficient arguments"
    show_usage
fi

SSH_HOST="$1"
LOCAL_FILE="$2"
REMOTE_PATH="$3"
SSH_PASSWORD=""

# Parse optional password argument
shift 3
while [[ $# -gt 0 ]]; do
    case $1 in
        --pw)
            SSH_PASSWORD="$2"
            shift 2
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            ;;
    esac
done

# Display header
echo ""
echo "======================================"
echo "   SSH File Upload Script"
echo "======================================"
print_info "SSH Host: ${SSH_HOST}"
print_info "Local file: ${LOCAL_FILE}"
print_info "Remote path: ${REMOTE_PATH}"
echo "======================================"
echo ""

# Validate local file/directory exists
if [ ! -e "${LOCAL_FILE}" ]; then
    print_error "Local file/directory not found: ${LOCAL_FILE}"
    exit 1
fi

# Get file/directory information
if [ -d "${LOCAL_FILE}" ]; then
    FILE_TYPE="directory"
    FILE_SIZE=$(du -sh "${LOCAL_FILE}" | cut -f1)
    FILE_COUNT=$(find "${LOCAL_FILE}" -type f | wc -l)
    print_info "Type: Directory (${FILE_COUNT} files)"
    print_info "Size: ${FILE_SIZE}"
else
    FILE_TYPE="file"
    FILE_SIZE=$(du -sh "${LOCAL_FILE}" | cut -f1)
    print_info "Type: File"
    print_info "Size: ${FILE_SIZE}"
fi
echo ""

# Check for required tools
USE_RSYNC=false
USE_SSHPASS=false

if command -v rsync &> /dev/null; then
    USE_RSYNC=true
    TRANSFER_TOOL="rsync"
else
    print_error "rsync not found! rsync is required for resumable uploads with progress."
    print_info "Install rsync: sudo apt-get install rsync"
    print_warning "Falling back to scp (NO resume support, NO progress display)"
    TRANSFER_TOOL="scp"
fi

if [ -n "${SSH_PASSWORD}" ]; then
    if command -v sshpass &> /dev/null; then
        USE_SSHPASS=true
    else
        print_error "Password provided but sshpass not found"
        print_info "Install sshpass: sudo apt-get install sshpass"
        exit 1
    fi
fi

print_info "Transfer method: ${TRANSFER_TOOL}"
if [ "$USE_SSHPASS" = true ]; then
    print_info "Authentication: Password"
else
    print_info "Authentication: SSH key"
fi
echo ""

# Build the transfer command
if [ "$USE_RSYNC" = true ]; then
    # rsync with resume capability and progress display
    # --partial: keep partially transferred files for resume
    # --partial-dir: store partial files in specific directory
    # --progress: show progress during transfer
    # -a: archive mode (preserves permissions, timestamps, etc.)
    # -v: verbose
    # -z: compress during transfer
    # -h: human-readable numbers
    # --info=progress2: better progress display (overall progress)
    RSYNC_OPTS="-avzh --partial --partial-dir=.rsync-partial --info=progress2"

    if [ "$USE_SSHPASS" = true ]; then
        # Use rsync with sshpass
        TRANSFER_CMD="sshpass -p '${SSH_PASSWORD}' rsync ${RSYNC_OPTS} -e 'ssh -o StrictHostKeyChecking=no' '${LOCAL_FILE}' '${SSH_HOST}:${REMOTE_PATH}'"
    else
        # Use rsync with SSH key
        TRANSFER_CMD="rsync ${RSYNC_OPTS} '${LOCAL_FILE}' '${SSH_HOST}:${REMOTE_PATH}'"
    fi
else
    # Fallback to scp (no resume support)
    SCP_OPTS="-r"

    if [ "$USE_SSHPASS" = true ]; then
        # Use scp with sshpass
        TRANSFER_CMD="sshpass -p '${SSH_PASSWORD}' scp ${SCP_OPTS} -o StrictHostKeyChecking=no '${LOCAL_FILE}' '${SSH_HOST}:${REMOTE_PATH}'"
    else
        # Use scp with SSH key
        TRANSFER_CMD="scp ${SCP_OPTS} '${LOCAL_FILE}' '${SSH_HOST}:${REMOTE_PATH}'"
    fi
fi

# Start transfer
print_info "Starting upload..."
if [ "$USE_RSYNC" = true ]; then
    print_info "Resume support: ENABLED (connection drops will resume from last position)"
else
    print_warning "Resume support: DISABLED (connection drops require full re-transfer)"
fi
echo ""

START_TIME=$(date +%s)

# Execute the transfer command
if [ "$USE_SSHPASS" = true ]; then
    if [ "$USE_RSYNC" = true ]; then
        sshpass -p "${SSH_PASSWORD}" rsync ${RSYNC_OPTS} -e 'ssh -o StrictHostKeyChecking=no' "${LOCAL_FILE}" "${SSH_HOST}:${REMOTE_PATH}"
    else
        sshpass -p "${SSH_PASSWORD}" scp ${SCP_OPTS} -o StrictHostKeyChecking=no "${LOCAL_FILE}" "${SSH_HOST}:${REMOTE_PATH}"
    fi
else
    if [ "$USE_RSYNC" = true ]; then
        rsync ${RSYNC_OPTS} "${LOCAL_FILE}" "${SSH_HOST}:${REMOTE_PATH}"
    else
        scp ${SCP_OPTS} "${LOCAL_FILE}" "${SSH_HOST}:${REMOTE_PATH}"
    fi
fi

TRANSFER_STATUS=$?

# Check if transfer was successful or interrupted
if [ $TRANSFER_STATUS -ne 0 ]; then
    echo ""
    print_error "Transfer interrupted or failed (exit code: ${TRANSFER_STATUS})"
    if [ "$USE_RSYNC" = true ]; then
        print_info "Partial files saved. Re-run the same command to resume from where it stopped."
    else
        print_warning "No resume support with scp. You'll need to start over."
    fi
    exit $TRANSFER_STATUS
fi

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# Format duration
if [ $DURATION -ge 60 ]; then
    DURATION_MIN=$((DURATION / 60))
    DURATION_SEC=$((DURATION % 60))
    DURATION_STR="${DURATION_MIN}m ${DURATION_SEC}s"
else
    DURATION_STR="${DURATION}s"
fi

echo ""
echo "======================================"
print_success "Upload completed successfully!"
echo "======================================"
print_info "Duration: ${DURATION_STR}"
print_info "Remote location: ${SSH_HOST}:${REMOTE_PATH}"
echo "======================================"
echo ""

# Verify the upload (optional)
print_info "Verifying upload..."
if [ "$USE_SSHPASS" = true ]; then
    REMOTE_CHECK=$(sshpass -p "${SSH_PASSWORD}" ssh -o StrictHostKeyChecking=no "${SSH_HOST}" "ls -lh '${REMOTE_PATH}' 2>/dev/null || echo 'CHECK_FAILED'")
else
    REMOTE_CHECK=$(ssh "${SSH_HOST}" "ls -lh '${REMOTE_PATH}' 2>/dev/null || echo 'CHECK_FAILED'")
fi

if echo "${REMOTE_CHECK}" | grep -q "CHECK_FAILED"; then
    print_warning "Could not verify remote file (check permissions)"
else
    print_success "Remote file verified"
fi

echo ""
