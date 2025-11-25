#!/usr/bin/env bash
#
# Quick X11 GUI sanity check for the terminal container.
# Starts a one-off vscode-airgap-terminal container with X11 forwarding
# wired to WSLg and runs xclock. If a clock window appears, the GUI
# path from Podman → WSLg is working.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

IMAGE="localhost/vscode-airgap-terminal:latest"
CONTAINER_NAME="vscode-terminal-x11-test"

echo "[info] Checking for terminal image: $IMAGE"
if ! podman image exists "$IMAGE" 2>/dev/null; then
  echo "[info] Building $IMAGE from terminal.Dockerfile ..."
  podman build --no-cache -f terminal.Dockerfile -t "$IMAGE" .
fi

echo "[info] Ensuring WSLg X11 socket exists at /mnt/wslg/.X11-unix ..."
if ! podman machine ssh podman-machine-default 'test -S /mnt/wslg/.X11-unix/X0' 2>/dev/null; then
  echo "[error] /mnt/wslg/.X11-unix/X0 not found inside podman machine."
  echo "        Make sure WSLg is running and Podman is configured to use it."
  exit 1
fi

echo "[info] Starting test container $CONTAINER_NAME with X11 forwarding ..."
echo "       If everything is wired correctly, an xclock window should appear."

podman run --rm -it \
  --name "$CONTAINER_NAME" \
  -e DISPLAY=":0" \
  -v /mnt/wslg/.X11-unix:/tmp/.X11-unix \
  "$IMAGE" \
  xclock

