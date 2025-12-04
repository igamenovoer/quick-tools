#!/usr/bin/env bash
set -euo pipefail

# add-mcp-context7.sh
# Ensure the Context7 MCP server is configured for Claude Code.
# If it already exists under the chosen scope, it is removed first, then re-added.
#
# Default behavior: scope = user, mcp-name = context7-mcp
# Runner preference: bunx > npx (picks first available)
# Note: context7-mcp is only available as npm package, uvx is not supported.
# Command used to add (example with npx):
#   claude mcp add-json -s user context7-mcp '{"command":"npx","args":["-y","@upstash/context7-mcp"]}'
#
# Options:
#   -s / --scope <scope>    Override scope: local, user, or project (default: user)
#   --mcp-name <name>       Override MCP server name (default: context7-mcp)
#   --dry-run               Show actions without executing
#   -q / --quiet            Less output
#   -h / --help             Show usage
#
# Exit codes:
#   0 success
#   1 generic error (missing prereq / command failure)

SCRIPT_NAME=$(basename "$0")
SCOPE="user"
MCP_NAME="context7-mcp"
DRY_RUN=0
QUIET=0

COLOR_DIM="\033[2m"; COLOR_OK="\033[32m"; COLOR_WARN="\033[33m"; COLOR_ERR="\033[31m"; COLOR_RESET="\033[0m"

log(){ [[ $QUIET -eq 1 ]] && return 0; printf "%b[%s]%b %s\n" "$COLOR_DIM" "$SCRIPT_NAME" "$COLOR_RESET" "$*"; }
ok(){ printf "%b[%s]%b %s\n" "$COLOR_OK" "$SCRIPT_NAME" "$COLOR_RESET" "$*"; }
warn(){ printf "%b[%s WARN]%b %s\n" "$COLOR_WARN" "$SCRIPT_NAME" "$COLOR_RESET" "$*" >&2; }
err(){ printf "%b[%s ERROR]%b %s\n" "$COLOR_ERR" "$SCRIPT_NAME" "$COLOR_RESET" "$*" >&2; }
die(){ err "$*"; exit 1; }

usage(){ grep -E '^# ' "$0" | sed 's/^# //'; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    -s|--scope) shift; SCOPE=${1:-}; [[ -z $SCOPE ]] && die "--scope requires value" ;;
    --mcp-name) shift; MCP_NAME=${1:-}; [[ -z $MCP_NAME ]] && die "--mcp-name requires value" ;;
    --dry-run) DRY_RUN=1 ;;
    -q|--quiet) QUIET=1 ;;
    *) die "Unknown argument: $1" ;;
  esac
  shift || true
done

[[ $SCOPE != "local" && $SCOPE != "user" && $SCOPE != "project" ]] && die "Invalid scope '$SCOPE' (expected local|user|project)"

command -v claude >/dev/null 2>&1 || die "'claude' CLI not found in PATH"

# Detect runner: bunx > npx (context7-mcp is npm-only, no PyPI package)
detect_runner(){
  if command -v bunx >/dev/null 2>&1; then
    echo "bunx"
  elif command -v npx >/dev/null 2>&1; then
    echo "npx"
  else
    die "No suitable runner found (bunx or npx required; context7-mcp is npm-only)"
  fi
}

RUNNER=$(detect_runner)
log "Using runner: $RUNNER"

server_exists(){
  # Using list + grep; tolerate list failures
  local list
  if ! list=$(claude mcp list 2>/dev/null); then
    warn "Could not list MCP servers (continuing)."
    return 1
  fi
  # Match server name at start of line followed by colon (e.g., "context7-mcp: ...")
  echo "$list" | grep -qE "^${MCP_NAME}:"
}

remove_server(){
  log "Removing existing $MCP_NAME (scope=$SCOPE)"
  if [[ $DRY_RUN -eq 1 ]]; then
    log "DRY-RUN: claude mcp remove -s $SCOPE $MCP_NAME"
    return 0
  fi
  # Ignore errors - server may not exist
  claude mcp remove -s "$SCOPE" "$MCP_NAME" 2>/dev/null || true
}

add_server(){
  log "Adding $MCP_NAME via $RUNNER (scope=$SCOPE)"
  
  # Build JSON config based on runner
  local json_config
  case "$RUNNER" in
    bunx)
      json_config='{"command":"bunx","args":["@upstash/context7-mcp"]}'
      ;;
    npx)
      json_config='{"command":"npx","args":["-y","@upstash/context7-mcp"]}'
      ;;
  esac
  
  if [[ $DRY_RUN -eq 1 ]]; then
    log "DRY-RUN: claude mcp add-json -s $SCOPE $MCP_NAME '$json_config'"
    return 0
  fi
  
  claude mcp add-json -s "$SCOPE" "$MCP_NAME" "$json_config"
}

main(){
  # Always remove first to ensure clean overwrite
  remove_server
  
  add_server
  
  if server_exists; then
    ok "$MCP_NAME configured successfully (scope=$SCOPE) using $RUNNER"
  else
    if [[ $DRY_RUN -eq 1 ]]; then
      ok "DRY-RUN complete (no changes applied)"
    else
      warn "$MCP_NAME not detected after add (check 'claude mcp list')."
    fi
  fi
}

main "$@"
