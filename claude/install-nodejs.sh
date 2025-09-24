#!/usr/bin/env bash
set -euo pipefail

# install-nodejs.sh
# Purpose: Install (or update) nvm (latest tag dynamically) and a Node.js runtime (>=18, default LTS)
# WITHOUT hard-coding the nvm version.
#
# Behaviors:
# - Detect existing nvm; skip unless --force-nvm given
# - Fetch latest nvm tag via GitHub API, fallback to git ls-remote parsing
# - Install nvm to $NVM_DIR (default: $HOME/.nvm)
# - Install Node (LTS by default) if missing or < 18 unless --only-nvm
# - Allow specifying a Node version via --node <ver> (e.g. 20, 20.11.1)
# - Idempotent; safe to re-run
#
# Usage examples:
#   ./install-nodejs.sh                 # install nvm (if needed) + LTS node (if needed)
#   ./install-nodejs.sh --node 20       # ensure Node 20.x
#   ./install-nodejs.sh --only-nvm      # just install/update nvm, no Node install
#   ./install-nodejs.sh --force-nvm     # reinstall nvm even if present
#   ./install-nodejs.sh --force-node    # reinstall selected (or LTS) Node version
#
# After running you can source your shell rc or start a new shell and run: node -v; npm -v

SCRIPT_NAME=$(basename "$0")
NODE_VERSION_REQUEST=""
ONLY_NVM=0
FORCE_NVM=0
FORCE_NODE=0
QUIET=0

COLOR_WARN="\033[33m"; COLOR_ERR="\033[31m"; COLOR_OK="\033[32m"; COLOR_DIM="\033[2m"; COLOR_RESET="\033[0m"

log(){ [[ $QUIET -eq 1 ]] && return 0; printf "%b[%s]%b %s\n" "$COLOR_DIM" "$SCRIPT_NAME" "$COLOR_RESET" "$*"; }
warn(){ printf "%b[%s WARN]%b %s\n" "$COLOR_WARN" "$SCRIPT_NAME" "$COLOR_RESET" "$*" >&2; }
err(){ printf "%b[%s ERROR]%b %s\n" "$COLOR_ERR" "$SCRIPT_NAME" "$COLOR_RESET" "$*" >&2; }
ok(){ printf "%b[%s]%b %s\n" "$COLOR_OK" "$SCRIPT_NAME" "$COLOR_RESET" "$*"; }
die(){ err "$*"; exit 1; }

usage(){ grep -E '^# ' "$0" | sed 's/^# //'; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --node) shift; NODE_VERSION_REQUEST=${1:-}; [[ -z $NODE_VERSION_REQUEST ]] && die "--node requires a version" ;;
    --only-nvm) ONLY_NVM=1 ;;
    --force-nvm) FORCE_NVM=1 ;;
    --force-node) FORCE_NODE=1 ;;
    --quiet|-q) QUIET=1 ;;
    *) die "Unknown argument: $1" ;;
  esac
  shift || true
done

have_cmd(){ command -v "$1" >/dev/null 2>&1; }

detect_latest_nvm_tag(){
  local tag
  if have_cmd curl; then
    tag=$(curl -fsSL https://api.github.com/repos/nvm-sh/nvm/releases/latest 2>/dev/null | grep -Eo '"tag_name": *"v[0-9.]+"' | head -n1 | grep -Eo 'v[0-9.]+' || true)
  fi
  if [[ -z $tag ]]; then
    if have_cmd git; then
      tag=$(git ls-remote --tags --refs https://github.com/nvm-sh/nvm.git 2>/dev/null | awk -F/ '{print $NF}' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+' | sort -V | tail -n1 || true)
    fi
  fi
  if [[ -z $tag ]]; then
    warn "Could not detect latest nvm tag; falling back to v0.39.7"
    tag="v0.39.7"
  fi
  printf "%s" "$tag"
}

install_nvm(){
  export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
  if [[ -s "$NVM_DIR/nvm.sh" && $FORCE_NVM -eq 0 ]]; then
    log "nvm already present at $NVM_DIR (use --force-nvm to reinstall)"
    return 0
  fi
  local tag; tag=$(detect_latest_nvm_tag)
  log "Installing nvm $tag into $NVM_DIR"
  if have_cmd curl; then
    curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/${tag}/install.sh" | bash
  elif have_cmd wget; then
    wget -qO- "https://raw.githubusercontent.com/nvm-sh/nvm/${tag}/install.sh" | bash
  else
    die "Need curl or wget to fetch nvm."
  fi
}

ensure_node(){
  # shellcheck disable=SC1090
  . "$NVM_DIR/nvm.sh"
  local current_ver="" current_major="" target_spec
  if have_cmd node; then
    current_ver=$(node -v | sed 's/^v//')
    current_major=${current_ver%%.*}
  fi
  if [[ -n $NODE_VERSION_REQUEST ]]; then
    target_spec="$NODE_VERSION_REQUEST"
  else
    target_spec="--lts"
  fi
  if [[ $FORCE_NODE -eq 1 ]]; then
    log "Forcing Node install ($target_spec)"
    nvm install "$target_spec"
    nvm alias default "$target_spec" || true
    return
  fi
  if [[ -z $current_ver || $current_major -lt 18 ]]; then
    log "Installing Node $target_spec (current: ${current_ver:-none})"
    nvm install "$target_spec"
    nvm alias default "$target_spec" || true
  else
    log "Node $current_ver already satisfies >=18 (use --force-node to reinstall)"
  fi
}

main(){
  install_nvm
  # shellcheck disable=SC1090
  . "${NVM_DIR:-$HOME/.nvm}/nvm.sh"
  if [[ $ONLY_NVM -eq 0 ]]; then
    ensure_node
  fi
  ok "Done. nvm version: $(nvm --version 2>/dev/null || echo n/a); node: $(command -v node >/dev/null && node -v || echo n/a)"
  log "Open a new shell or: source $NVM_DIR/nvm.sh"
}

main "$@"
