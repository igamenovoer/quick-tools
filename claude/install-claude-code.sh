#!/usr/bin/env bash
set -euo pipefail

# install-claude-code.sh
# Purpose: Idempotently install / update the latest Claude Code CLI (@anthropic-ai/claude-code)
# without requiring sudo, setting up a user-level npm global prefix when needed.
#
# Key behaviors:
# - Requires Node.js (>=18) & npm pre-installed (see ./instrall-nodejs.sh)
# - Avoids sudo; uses user prefix fallback on EACCES
# - Adds prefix/bin to PATH in common shells if missing
# - Skips reinstall if already present unless --force
# - Minimal, auditable; safe for repeated runs
#
# Usage:
#   ./install-claude-code.sh            # normal install / update
#   ./install-claude-code.sh --force    # force reinstall
#   ./install-nodejs.sh                 # run this first if Node >=18 not installed
#   ./install-claude-code.sh --quiet    # reduce log noise
#
# After completion you should be able to run:
#   claude --version

SCRIPT_NAME=$(basename "$0")
FORCE=0
QUIET=0

COLOR_OK="\033[32m"
COLOR_WARN="\033[33m"
COLOR_ERR="\033[31m"
COLOR_DIM="\033[2m"
COLOR_RESET="\033[0m"

log() {
	if [[ $QUIET -eq 1 ]]; then return 0; fi
	printf "%b[%s]%b %s\n" "${COLOR_DIM}" "$SCRIPT_NAME" "${COLOR_RESET}" "$*"
}

info() { log "$*"; }
warn() { printf "%b[%s WARN]%b %s\n" "${COLOR_WARN}" "$SCRIPT_NAME" "${COLOR_RESET}" "$*" >&2; }
err()  { printf "%b[%s ERROR]%b %s\n" "${COLOR_ERR}" "$SCRIPT_NAME" "${COLOR_RESET}" "$*" >&2; }
ok()   { printf "%b[%s]%b %s\n" "${COLOR_OK}" "$SCRIPT_NAME" "${COLOR_RESET}" "$*"; }

die() { err "$*"; exit 1; }

usage() {
	grep -E '^# ' "$0" | sed 's/^# //'
}

while [[ $# -gt 0 ]]; do
	case "$1" in
		-h|--help) usage; exit 0 ;;
		--force) FORCE=1 ;;
		--quiet|-q) QUIET=1 ;;
		*) die "Unknown argument: $1" ;;
	esac
	shift
done

require_cmd() {
	command -v "$1" >/dev/null 2>&1 || die "Required command '$1' not found"
}

have_cmd() { command -v "$1" >/dev/null 2>&1; }

ensure_node() {
	if have_cmd node && have_cmd npm; then
		local ver major
		ver=$(node --version | sed 's/^v//')
		major=${ver%%.*}
		if [[ $major -ge 18 ]]; then
			return 0
		fi
		die "Node version $ver < 18. Please run ./install-nodejs.sh first."
	else
		die "node/npm not found. Please run ./install-nodejs.sh to install nvm + Node LTS."
	fi
}

install_claude() {
	local pkg="@anthropic-ai/claude-code"
	info "Installing latest $pkg (no sudo)..."
	if npm install -g "$pkg" 2> >(tee /tmp/claude-install.err >&2); then
		return 0
	fi

	if grep -qiE 'EACCES|permission denied' /tmp/claude-install.err; then
		warn "Global install failed due to permissions; configuring user npm prefix."
		local prefix="$HOME/.npm-global"
		mkdir -p "$prefix"
		npm config set prefix "$prefix"
		ensure_path "$prefix/bin"
		info "Retrying install with user prefix..."
		npm install -g "$pkg" || die "Install failed again even after prefix setup."
	else
		die "npm install failed (see above)."
	fi
}

ensure_path() {
	local binpath="$1"
	case ":$PATH:" in
		*":$binpath:"*) return 0 ;;
	esac
	warn "PATH missing $binpath; attempting to add to shell rc."
	local added=0
	for rc in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
		if [[ -f $rc ]]; then
			if ! grep -F "$binpath" "$rc" >/dev/null 2>&1; then
				printf '\n# Added by %s on %s\nexport PATH="%s:$PATH"\n' "$SCRIPT_NAME" "$(date -u +%Y-%m-%d)" "$binpath" >> "$rc"
				added=1
			fi
		fi
	done
	if [[ $added -eq 0 ]]; then
		# fallback create .bashrc
		printf '\n# Added by %s on %s\nexport PATH="%s:$PATH"\n' "$SCRIPT_NAME" "$(date -u +%Y-%m-%d)" "$binpath" >> "$HOME/.bashrc"
	fi
	export PATH="$binpath:$PATH"
}

already_installed() {
	if ! have_cmd claude; then return 1; fi
	# Try to detect if it's the Anthropic CLI by running version/help
	if claude --version >/dev/null 2>&1 || claude -v >/dev/null 2>&1; then
		return 0
	fi
	return 1
}

main() {
	if [[ $FORCE -eq 0 ]] && already_installed; then
		ok "Claude Code already installed. Use --force to reinstall."
		claude --version 2>/dev/null || true
		exit 0
	fi

	ensure_node

	# Ensure npm global bin path is in PATH (common locations)
	for p in "$HOME/.npm-global/bin" "$HOME/.nvm/versions/node"/*/bin; do
		if [[ -d $p ]]; then ensure_path "$p"; break; fi
	done

	install_claude

	if claude --version >/dev/null 2>&1; then
		ok "Claude Code installed: $(claude --version 2>/dev/null | head -n1)"
	else
		warn "Install finished but 'claude --version' failed; check PATH and npm prefix."
	fi
	info "You may need to restart your shell for PATH changes to take effect."
}

main "$@"

