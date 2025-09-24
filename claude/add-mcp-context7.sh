#!/usr/bin/env bash
set -euo pipefail

# add-mcp-context7.sh
# Ensure the Context7 MCP server is configured for Claude Code.
# If it already exists under the chosen scope, it is removed first, then re-added.
#
# Default behavior: scope = user
# Command used to add:
#   claude mcp add -s user context7-mcp -- npx -y @upstash/context7-mcp
#
# Options:
#   --scope <user|global>   Override scope (default: user)
#   --dry-run               Show actions without executing
#   --no-replace            Skip re-adding if already present (exit 0)
#   --force                 Continue even if removal reports not found
#   -q / --quiet            Less output
#   -h / --help             Show usage
#
# Exit codes:
#   0 success
#   1 generic error (missing prereq / command failure)

SCRIPT_NAME=$(basename "$0")
SCOPE="user"
DRY_RUN=0
NO_REPLACE=0
FORCE=0
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
    --scope) shift; SCOPE=${1:-}; [[ -z $SCOPE ]] && die "--scope requires value" ;;
    --dry-run) DRY_RUN=1 ;;
    --no-replace) NO_REPLACE=1 ;;
    --force) FORCE=1 ;;
    -q|--quiet) QUIET=1 ;;
    *) die "Unknown argument: $1" ;;
  esac
  shift || true
done

[[ $SCOPE != "user" && $SCOPE != "global" ]] && die "Invalid scope '$SCOPE' (expected user|global)"

command -v claude >/dev/null 2>&1 || die "'claude' CLI not found in PATH"

server_exists(){
  # Using list + grep; tolerate list failures
  local list
  if ! list=$(claude mcp list 2>/dev/null); then
    warn "Could not list MCP servers (continuing)."
    return 1
  fi
  # Simple substring match; refine if list format changes
  echo "$list" | grep -qE "(^|[[:space:]])context7-mcp( |$)"
}

remove_server(){
  log "Removing existing context7-mcp (scope=$SCOPE)"
  if [[ $DRY_RUN -eq 1 ]]; then
    log "DRY-RUN: claude mcp remove -s $SCOPE context7-mcp"
    return 0
  fi
  if ! claude mcp remove -s "$SCOPE" context7-mcp 2>&1; then
    if [[ $FORCE -eq 1 ]]; then
      warn "Removal reported an issue; continuing due to --force"
    else
      warn "Removal failed; continuing to add anyway"
    fi
  fi
}

add_server(){
  log "Adding context7-mcp via npx (scope=$SCOPE)"
  local cmd=(claude mcp add -s "$SCOPE" context7-mcp -- npx -y @upstash/context7-mcp)
  if [[ $DRY_RUN -eq 1 ]]; then
    log "DRY-RUN: ${cmd[*]}"
    return 0
  fi
  "${cmd[@]}"
}

main(){
  if server_exists; then
    if [[ $NO_REPLACE -eq 1 ]]; then
      ok "context7-mcp already present (scope=$SCOPE); skipping due to --no-replace"
      exit 0
    fi
    remove_server
  else
    log "context7-mcp not currently configured for scope=$SCOPE"
  fi
  add_server
  if server_exists; then
    ok "context7-mcp configured successfully (scope=$SCOPE)"
  else
    if [[ $DRY_RUN -eq 1 ]]; then
      ok "DRY-RUN complete (no changes applied)"
    else
      warn "context7-mcp not detected after add (check 'claude mcp list')."
    fi
  fi
}

main "$@"
