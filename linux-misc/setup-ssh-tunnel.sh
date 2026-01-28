#!/bin/bash

# Defaults
REMOTE_PORT=5555
KEEP_ALIVE=60

# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --remote-port) REMOTE_PORT="$2"; shift ;;
        --keep-alive) KEEP_ALIVE="$2"; shift ;;
        *) echo "Unknown parameter: $1"; exit 1 ;;
    esac
    shift
done

# Configuration
TUNNEL_CMD="ssh -o ServerAliveInterval=${KEEP_ALIVE} -f -N -R ${REMOTE_PORT}:0.0.0.0:22 ssh-tun"
SEARCH_PATTERN="${REMOTE_PORT}:0.0.0.0:22"

# Check if the tunnel is already running and restart it
if pgrep -f "$SEARCH_PATTERN" | grep -v "$$" > /dev/null; then
    echo "SSH tunnel is already running (port ${REMOTE_PORT}). Killing existing process(es)..."
    pgrep -f "$SEARCH_PATTERN" | grep -v "$$" | xargs kill -9 2>/dev/null
    sleep 1
fi

echo "Starting SSH tunnel on remote port ${REMOTE_PORT} with keep-alive ${KEEP_ALIVE}s..."
$TUNNEL_CMD
if [ $? -eq 0 ]; then
    echo "SSH tunnel started successfully in the background."
    echo ""
    echo "=== Quick Connection Guide ==="
    echo "To connect from outside, use:"
    echo "  ssh -p ${REMOTE_PORT} huangzhe@112.74.107.214"
    echo ""
    echo "Note: Ensure 'GatewayPorts yes' is set in the remote server's /etc/ssh/sshd_config"
    echo "and port ${REMOTE_PORT} is open in the remote firewall."
    echo "=============================="
else
    echo "Failed to start SSH tunnel."
fi
