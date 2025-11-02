#!/usr/bin/env bash
# Enable tmux mouse scrolling and sane scroll speed.
# - Adds `set -g mouse on` and increases history-limit
# - Adds wheel bindings to auto-enter copy-mode and scroll 1 line per tick
# - Makes a timestamped backup of existing ~/.tmux.conf
# - Reloads tmux config if a tmux server is running
#
# Usage:
#   bash tmux-enable-mouse-scroll.sh [--limit N]
#     --limit N   Set tmux history-limit to N (default: 5000)
# Idempotent: running multiple times will not duplicate settings.

set -euo pipefail

TMUX_CONF="${HOME}/.tmux.conf"
BACKUP_DIR="${HOME}/.tmux-backups"

mkdir -p "${BACKUP_DIR}"

# Defaults
HISTORY_LIMIT=5000

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --limit)
      if [[ $# -lt 2 ]]; then
        echo "Error: --limit requires a value" >&2
        exit 1
      fi
      HISTORY_LIMIT="$2"
      shift 2
      ;;
    -h|--help)
      grep '^# ' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      echo "Use --help for usage." >&2
      exit 1
      ;;
  esac
done

# Validate limit
if ! [[ "$HISTORY_LIMIT" =~ ^[0-9]+$ ]] || [[ "$HISTORY_LIMIT" -le 0 ]]; then
  echo "Error: --limit must be a positive integer" >&2
  exit 1
fi

# Create file if missing
if [[ ! -f "${TMUX_CONF}" ]]; then
  touch "${TMUX_CONF}"
fi

# Backup current config
STAMP=$(date +%Y%m%d-%H%M%S)
cp "${TMUX_CONF}" "${BACKUP_DIR}/tmux.conf.${STAMP}.bak"
echo "Backed up ${TMUX_CONF} -> ${BACKUP_DIR}/tmux.conf.${STAMP}.bak"
echo "Using history-limit: ${HISTORY_LIMIT}"

# Desired config block
# Note: read -r -d '' returns exit code 1, so we capture it with || true
read -r -d '' CONFIG_BLOCK <<'EOF' || true
# --- BEGIN auto-added by tmux-enable-mouse-scroll.sh ---
# Enable mouse support (scroll, pane resize, selection)
set -g mouse on

# Increase scrollback history so wheel scrolling is useful
set -g history-limit HISTORY_LIMIT_PLACEHOLDER

# Smoother wheel behavior: auto-enter copy-mode and scroll 1 line per tick
# Works for both default and vi copy-mode key tables
bind -n WheelUpPane if-shell -F '#{pane_in_mode}' \
  'send-keys -X -N 1 scroll-up' \
  'copy-mode -e; send-keys -X -N 1 scroll-up'

bind -n WheelDownPane if-shell -F '#{pane_in_mode}' \
  'send-keys -X -N 1 scroll-down' \
  'send-keys -X -N 1 scroll-down'

bind -T copy-mode-vi WheelUpPane   send-keys -X -N 1 scroll-up
bind -T copy-mode-vi WheelDownPane send-keys -X -N 1 scroll-down
# --- END auto-added by tmux-enable-mouse-scroll.sh ---
EOF

# Substitute the actual history limit value
CONFIG_BLOCK="${CONFIG_BLOCK//HISTORY_LIMIT_PLACEHOLDER/$HISTORY_LIMIT}"

# Remove any previous auto-added block to keep things clean/idempotent
if grep -q "BEGIN auto-added by tmux-enable-mouse-scroll.sh" "${TMUX_CONF}"; then
  # Use awk to strip the block
  awk '
    BEGIN {skip=0}
    /# --- BEGIN auto-added by tmux-enable-mouse-scroll.sh ---/ {skip=1; next}
    /# --- END auto-added by tmux-enable-mouse-scroll.sh ---/ {skip=0; next}
    skip==0 {print}
  ' "${TMUX_CONF}" > "${TMUX_CONF}.tmp"
  mv "${TMUX_CONF}.tmp" "${TMUX_CONF}"
  echo "Removed previous auto-added tmux mouse scroll block."
fi

# Append fresh block
printf "\n%s\n" "${CONFIG_BLOCK}" >> "${TMUX_CONF}"
echo "Updated ${TMUX_CONF} with tmux mouse scroll configuration."

# Try to reload tmux if server is running
if tmux info >/dev/null 2>&1 || tmux display-message -p '#S' >/dev/null 2>&1; then
  if tmux source-file "${TMUX_CONF}" >/dev/null 2>&1; then
    echo "Reloaded tmux configuration in running server."
  else
    echo "tmux server detected but reload failed; you can reload inside tmux with: tmux source-file ~/.tmux.conf"
  fi
else
  echo "No running tmux server detected. New sessions will use the updated config."
fi

cat <<NOTE
Done. Tips:
- In tmux, use the mouse wheel to scroll; press 'q' or 'Esc' to exit copy-mode.
- If host terminal scrolls instead of tmux, ensure focus is on the pane and this config is loaded.
NOTE
