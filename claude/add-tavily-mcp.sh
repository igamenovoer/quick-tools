#!/usr/bin/env bash
set -euo pipefail

# add-tavily-mcp.sh
# Ensure the Tavily MCP server is configured for Claude Code.
# If it already exists under the chosen scope, it is removed first, then re-added.
#
# Default behavior: scope = user, mcp-name = tavily
# Runner preference: npx > bunx > uvx (picks first available)
# Command used to add (example with npx):
#   claude mcp add-json -s user tavily '{"command":"npx","args":["-y","tavily-mcp@latest"],"env":{"TAVILY_API_KEY":"..."}}'
#
# Options:
#   -s / --scope <scope>    Override scope: local, user, or project (default: user)
#   --mcp-name <name>       Override MCP server name (default: tavily)
#   --dry-run               Show actions without executing
#   -q / --quiet            Less output
#   -h / --help             Show usage
#
# Exit codes:
#   0 success
#   1 generic error (missing prereq / command failure)

SCRIPT_NAME=$(basename "$0")
SCOPE="user"
MCP_NAME="tavily"
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

# Detect runner: npx > bunx > uvx
detect_runner(){
  if command -v npx >/dev/null 2>&1; then
    echo "npx"
  elif command -v bunx >/dev/null 2>&1; then
    echo "bunx"
  elif command -v uvx >/dev/null 2>&1; then
    echo "uvx"
  else
    die "No suitable runner found (bunx, npx, or uvx required)"
  fi
}

RUNNER=$(detect_runner)
log "Using runner: $RUNNER"

# Get Tavily API key: check env first, then prompt user
get_tavily_api_key(){
  if [[ -n "${TAVILY_API_KEY:-}" ]]; then
    log "TAVILY_API_KEY found in environment" >&2
    echo "$TAVILY_API_KEY"
  else
    log "TAVILY_API_KEY not found in environment, prompting user..." >&2
    echo "" >&2
    echo "Tavily API key is required. Get one at: https://app.tavily.com/home" >&2
    printf "Enter your Tavily API key: " >&2
    read -r api_key
    if [[ -z "$api_key" ]]; then
      die "Tavily API key cannot be empty"
    fi
    echo "$api_key"
  fi
}

server_exists(){
  local list
  if ! list=$(claude mcp list 2>/dev/null); then
    warn "Could not list MCP servers (continuing)."
    return 1
  fi
  echo "$list" | grep -qE "(^|[[:space:]])${MCP_NAME}( |$)"
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
  local api_key="$1"
  log "Adding $MCP_NAME via $RUNNER (scope=$SCOPE)"
  
  # Build JSON config based on runner
  local json_config
  case "$RUNNER" in
    bunx)
      json_config=$(cat <<EOF
{"command":"bunx","args":["tavily-mcp@latest"],"env":{"TAVILY_API_KEY":"${api_key}"}}
EOF
)
      ;;
    npx)
      json_config=$(cat <<EOF
{"command":"npx","args":["-y","tavily-mcp@latest"],"env":{"TAVILY_API_KEY":"${api_key}"}}
EOF
)
      ;;
    uvx)
      json_config=$(cat <<EOF
{"command":"uvx","args":["mcp-tavily"],"env":{"TAVILY_API_KEY":"${api_key}"}}
EOF
)
      ;;
  esac
  
  if [[ $DRY_RUN -eq 1 ]]; then
    log "DRY-RUN: claude mcp add-json -s $SCOPE $MCP_NAME '$json_config'"
    return 0
  fi
  
  claude mcp add-json -s "$SCOPE" "$MCP_NAME" "$json_config"
}

main(){
  local api_key
  
  # Get API key first (before any server operations)
  api_key=$(get_tavily_api_key)
  
  # Always remove first to ensure clean overwrite
  remove_server
  
  add_server "$api_key"
  
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
