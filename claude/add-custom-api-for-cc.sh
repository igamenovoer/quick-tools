#!/usr/bin/env bash
set -euo pipefail

# add-custom-api-for-cc.sh
# Create / update a shell alias that runs Claude Code against a custom-compatible
# Anthropic-style endpoint (e.g., Kimi K2, yunwu.ai, etc.) while skipping the
# interactive sign-in and permission prompts.
#
# Required args (or will prompt interactively if not provided unless --yes):
#   --alias <alias_name>        # name used after `alias`, e.g. claude-kimi
#   --base_url <url>            # base URL of the endpoint (must include protocol)
#   --api_key <key>             # API key string (prompt hidden)
#
# The script:
# - Validates inputs & alias name
# - Writes/updates alias lines in ~/.bashrc and ~/.zshrc (if present / for bash always ensures file)
# - Removes older conflicting alias definitions for the same alias
# - Uses: ANTHROPIC_BASE_URL, ANTHROPIC_API_KEY, and --dangerously-skip-permissions
# - Leaves existing unrelated lines untouched
#
# Resulting alias example:
#   alias claude-kimi='ANTHROPIC_BASE_URL="https://api.moonshot.cn/anthropic/" \
#     ANTHROPIC_API_KEY="sk-XXX" claude --dangerously-skip-permissions'
#
# After running, reload your shell or: source ~/.bashrc  (or ~/.zshrc)
#
# NOTE: To skip sign-in entirely you also need a settings file:
#   mkdir -p ~/.claude && echo '{"apiKeyHelper": "echo $ANTHROPIC_API_KEY"}' > ~/.claude/settings.json
# You may choose to do that manually if you do not want the API key echoed plainly.

SCRIPT_NAME=$(basename "$0")
ALIAS_NAME=""
BASE_URL=""
API_KEY=""
QUIET=0
DRY_RUN=0
YES_MODE=0

COLOR_OK="\033[32m"; COLOR_WARN="\033[33m"; COLOR_ERR="\033[31m"; COLOR_DIM="\033[2m"; COLOR_RESET="\033[0m"

log(){ [[ $QUIET -eq 1 ]] && return 0; printf "%b[%s]%b %s\n" "$COLOR_DIM" "$SCRIPT_NAME" "$COLOR_RESET" "$*"; }
warn(){ printf "%b[%s WARN]%b %s\n" "$COLOR_WARN" "$SCRIPT_NAME" "$COLOR_RESET" "$*" >&2; }
err(){ printf "%b[%s ERROR]%b %s\n" "$COLOR_ERR" "$SCRIPT_NAME" "$COLOR_RESET" "$*" >&2; }
ok(){ printf "%b[%s]%b %s\n" "$COLOR_OK" "$SCRIPT_NAME" "$COLOR_RESET" "$*"; }
die(){ err "$*"; exit 1; }

usage(){ grep -E '^# ' "$0" | sed 's/^# //'; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --alias) shift; ALIAS_NAME=${1:-}; [[ -z $ALIAS_NAME ]] && die "--alias requires a value" ;;
    --base_url) shift; BASE_URL=${1:-}; [[ -z $BASE_URL ]] && die "--base_url requires a value" ;;
    --api_key) shift; API_KEY=${1:-}; [[ -z $API_KEY ]] && die "--api_key requires a value" ;;
    --quiet|-q) QUIET=1 ;;
  --dry-run) DRY_RUN=1 ;;
  --yes) YES_MODE=1 ;;
    *) die "Unknown argument: $1" ;;
  esac
  shift || true
done

# Interactive prompting for missing fields if running in a TTY
if [[ -z $ALIAS_NAME ]]; then
  if [[ $YES_MODE -eq 1 ]]; then die "Missing --alias (required with --yes)"; fi
  if [[ -t 0 ]]; then read -rp "Alias name (--alias): " ALIAS_NAME; else die "Missing --alias"; fi
fi
if [[ -z $BASE_URL ]]; then
  if [[ $YES_MODE -eq 1 ]]; then die "Missing --base_url (required with --yes)"; fi
  if [[ -t 0 ]]; then read -rp "Base URL (--base_url): " BASE_URL; else die "Missing --base_url"; fi
fi
if [[ -z $API_KEY ]]; then
  if [[ $YES_MODE -eq 1 ]]; then die "Missing --api_key (required with --yes)"; fi
  if [[ -t 0 ]]; then read -srp "API key (--api_key, input hidden): " API_KEY; echo; else die "Missing --api_key"; fi
fi

# Re-check empties after prompting
[[ -z $ALIAS_NAME ]] && die "Alias name cannot be empty"
[[ -z $BASE_URL ]] && die "Base URL cannot be empty"
[[ -z $API_KEY ]] && die "API key cannot be empty"

# (settings.json handling moved to end; actual API key is now known.)

# Basic validations
if ! [[ $ALIAS_NAME =~ ^[A-Za-z0-9_-]+$ ]]; then
  die "Alias name '$ALIAS_NAME' has invalid characters (allowed: A-Za-z0-9_-)"
fi
if ! [[ $BASE_URL =~ ^https?:// ]]; then
  die "--base_url must start with http:// or https://"
fi

ALIAS_LINE="alias ${ALIAS_NAME}='ANTHROPIC_BASE_URL=\"${BASE_URL}\" ANTHROPIC_API_KEY=\"${API_KEY}\" claude --dangerously-skip-permissions'"

modify_rc(){
  local rc="$1"
  local tmp
  [[ ! -f $rc ]] && touch "$rc"
  tmp=$(mktemp)
  # Remove existing alias lines for this alias
  grep -v -E "^alias[ ]+${ALIAS_NAME}=" "$rc" > "$tmp" || true
  printf '\n# Added/updated by %s on %s for Claude Code custom endpoint (%s)\n%s\n' \
    "$SCRIPT_NAME" "$(date -u +%Y-%m-%d)" "$BASE_URL" "$ALIAS_LINE" >> "$tmp"
  if [[ $DRY_RUN -eq 1 ]]; then
    log "--- DRY RUN ($rc) would become:"
    tail -n 5 "$tmp" | sed 's/^/  /'
  else
    mv "$tmp" "$rc"
  fi
}

TARGET_RCS=("$HOME/.bashrc")
[[ -f $HOME/.zshrc ]] && TARGET_RCS+=("$HOME/.zshrc")

for rc in "${TARGET_RCS[@]}"; do
  modify_rc "$rc"
  log "Updated $rc"
done

if [[ $DRY_RUN -eq 0 ]]; then
  ok "Alias '${ALIAS_NAME}' added. Reload your shell or run: source ~/.bashrc"
  printf "%s\n" "$ALIAS_LINE" | sed 's/^/Alias: /'
else
  warn "Dry run mode: no files modified."
fi

# Final step: optionally update settings.json if it exists and has apiKeyHelper
finalize_settings() {
  local settings_dir="$HOME/.claude"
  local settings_file="$settings_dir/settings.json"
  
  # Only proceed if settings.json exists AND contains apiKeyHelper
  if [[ ! -f $settings_file ]]; then
    return 0
  fi
  if ! grep -q '"apiKeyHelper"' "$settings_file" 2>/dev/null; then
    return 0
  fi

  if [[ $DRY_RUN -eq 1 ]]; then
    warn "[dry-run] Would offer to update apiKeyHelper in $settings_file"
    return 0
  fi
  
  if [[ -t 0 ]]; then
    if [[ $YES_MODE -eq 1 ]]; then
      warn "--yes supplied; skipping settings.json update."
    else
      echo -n "Found existing apiKeyHelper in $settings_file. Update with new key? [y/N]: "
      read -r ans || ans=""
      if [[ $ans =~ ^[Yy]$ ]]; then
        # Check if jq is available
        if command -v jq >/dev/null 2>&1; then
          log "Using jq for JSON manipulation"
          
          # Backup existing file
          cp -p "$settings_file" "$settings_file.bak.$(date +%Y%m%d%H%M%S)"
          warn "Existing settings.json backed up"
          
          # Update existing config with apiKeyHelper
          if jq empty "$settings_file" 2>/dev/null; then
             jq --arg key "$API_KEY" '.apiKeyHelper = "echo " + $key' "$settings_file" > "$settings_file.tmp" && mv "$settings_file.tmp" "$settings_file"
             ok "Updated apiKeyHelper in $settings_file"
          else
             warn "Existing settings.json is invalid JSON. Skipping update."
          fi
        else
          log "jq not found, using raw string manipulation"
          
          cp -p "$settings_file" "$settings_file.bak.$(date +%Y%m%d%H%M%S)"
          warn "Existing settings.json backed up"
          
          # Read existing content
          local content
          content=$(cat "$settings_file" || echo "")
          
          # We know apiKeyHelper exists because of the grep check at the top
          if echo "$content" | sed "s|\"apiKeyHelper\"[[:space:]]*:[[:space:]]*\"[^\"]*\"|\"apiKeyHelper\": \"echo $API_KEY\"|" > "$settings_file"; then
             ok "Updated apiKeyHelper in $settings_file"
          else
             warn "Failed to update settings.json"
          fi
        fi
      else
        warn "Skipped settings.json update."
      fi
    fi
  else
    warn "Non-interactive: not updating settings.json."
  fi
}

finalize_settings


