#!/usr/bin/env bash
set -euo pipefail

# pixi-config.sh
# Configure Pixi mirrors for PyPI and conda-forge on Linux/WSL.
#
# Options:
#   --pypi-mirror=tuna|aliyun|official
#       Set PyPI mirror (affects [pypi-config].index-url and [mirrors] for PyPI).
#   --conda-forge-mirror=tuna|aliyun|official
#       Set conda-forge mirror (affects [mirrors] mapping for conda-forge).
#   -h|--help  Show usage
#
# Notes:
# - Writes to "$HOME/.pixi/config.toml" (creating it if needed).
# - Idempotent: updates or removes only the keys this script manages.
# - For PyPI, Pixi/uv may fetch via both https://pypi.org/simple and
#   https://files.pythonhosted.org; we mirror both.

usage() {
  cat <<'EOF'
Usage: wsl-setup/pixi-config.sh [--pypi-mirror=CHOICE] [--conda-forge-mirror=CHOICE]

CHOICE values:
  tuna      Tsinghua University mirrors (China)
  aliyun    Alibaba Cloud mirrors (China)
  official  Restore official upstreams

Examples:
  # Use TUNA for both PyPI and conda-forge
  wsl-setup/pixi-config.sh --pypi-mirror=tuna --conda-forge-mirror=tuna

  # Use Aliyun for PyPI, keep conda-forge official
  wsl-setup/pixi-config.sh --pypi-mirror=aliyun --conda-forge-mirror=official

This script modifies ~/.pixi/config.toml under sections:
  [pypi-config] -> index-url
  [mirrors]     -> maps original URLs to mirror URLs

EOF
}

PIPY_CHOICE=""
CF_CHOICE=""

for arg in "$@"; do
  case "$arg" in
    --pypi-mirror=*)
      PIPY_CHOICE="${arg#*=}";
      ;;
    --conda-forge-mirror=*)
      CF_CHOICE="${arg#*=}";
      ;;
    -h|--help)
      usage; exit 0;
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      usage
      exit 2
      ;;
  esac
done

validate_choice() {
  local name="$1" val="$2"
  case "$val" in
    tuna|aliyun|official|"") : ;; # empty allowed (no change)
    *) echo "Invalid $name: $val (expected tuna|aliyun|official)" >&2; exit 2;;
  esac
}

validate_choice "--pypi-mirror" "$PIPY_CHOICE"
validate_choice "--conda-forge-mirror" "$CF_CHOICE"

CONFIG_DIR="$HOME/.pixi"
CONFIG_FILE="$CONFIG_DIR/config.toml"
mkdir -p "$CONFIG_DIR"
touch "$CONFIG_FILE"

# Ensure a section exists; append header if missing.
ensure_section() {
  local section="$1"
  if ! grep -q "^\[$section\]" "$CONFIG_FILE"; then
    printf '\n[%s]\n' "$section" >>"$CONFIG_FILE"
  fi
}

# Update or set index-url in [pypi-config]. If value empty, remove the key.
set_pypi_index_url() {
  local value="$1"
  ensure_section "pypi-config"
  if [[ -z "$value" ]]; then
    # Remove index-url line within section
    awk '
      BEGIN{insec=0}
      /^\[pypi-config\]/{insec=1}
      /^[[]/{if ($0!~/^\[pypi-config\]/) insec=0}
      {
        if (insec && $0 ~ /^index-url[[:space:]]*=/) next;
        print $0;
      }
    ' "$CONFIG_FILE" >"$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
  else
    # Replace if exists, else insert right after the section header
    if awk 'BEGIN{insec=0; found=0}
             /^\[pypi-config\]/{insec=1}
             /^[[]/{if ($0!~/^\[pypi-config\]/) insec=0}
             { if (insec && $0 ~ /^index-url[[:space:]]*=/) { found=1 } }
             END{ exit(found?0:1) }' "$CONFIG_FILE"; then
      awk -v val="$value" '
        BEGIN{insec=0}
        /^\[pypi-config\]/{insec=1}
        /^[[]/{if ($0!~/^\[pypi-config\]/) insec=0}
        {
          if (insec && $0 ~ /^index-url[[:space:]]*=/) {
            print "index-url = \"" val "\""; next;
          }
          print $0;
        }
      ' "$CONFIG_FILE" >"$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    else
      awk -v val="$value" '
        BEGIN{insec=0}
        {
          print $0;
          if ($0 ~ /^\[pypi-config\]/) {
            insec=1;
            getline nextline;
            if (nextline !~ /^[[]/) {
              # Put back the read line and then insert key at top of section
              print "index-url = \"" val "\"";
              print nextline;
              insec=0;
            } else {
              # Empty section, insert before next section header we just read
              print "index-url = \"" val "\"";
              print nextline;
              insec=0;
            }
          }
        }
      ' "$CONFIG_FILE" >"$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
      # In edge cases where section is last and empty, ensure the key exists
      if ! grep -q "^index-url\s*=\s*\"" "$CONFIG_FILE"; then
        printf 'index-url = "%s"\n' "$value" >>"$CONFIG_FILE"
      fi
    fi
  fi
}

# Upsert a mirror mapping line in [mirrors]:
#   "<original>" = ["mirror", "fallback"]
# If value is empty, remove the line for that original.
set_mirror_mapping() {
  local original="$1"; shift
  local values=("$@")
  ensure_section "mirrors"
  if [[ ${#values[@]} -eq 0 || -z "${values[*]}" ]]; then
    # Remove line for original
    awk -v key="$original" '
      BEGIN{insec=0}
      /^\[mirrors\]/{insec=1}
      /^[[]/{if ($0!~/^\[mirrors\]/) insec=0}
      {
        if (insec && $0 ~ /^"/){
          # Escape regex metacharacters in key
          k=key; gsub(/[][(){}.^$*+?|\\]/, "\\\\&", k);
          pat = "^\"" k "\"[[:space:]]*=";
          if ($0 ~ pat) next;
        }
        print $0;
      }
    ' "$CONFIG_FILE" >"$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
  else
    local arr_line
    # Build TOML array string with comma separation
    local parts=()
    for v in "${values[@]}"; do parts+=("\"$v\""); done
    local joined=""
    local i
    for ((i=0; i<${#parts[@]}; i++)); do
      if (( i > 0 )); then joined+=" , "; fi
      joined+="${parts[i]}"
    done
    arr_line="\"$original\" = [${joined}]"

    if awk -v key="$original" 'BEGIN{insec=0; found=0}
             /^\[mirrors\]/{insec=1}
             /^[[]/{if ($0!~/^\[mirrors\]/) insec=0}
             {
               if (insec && $0 ~ /^"/){
                 k=key; gsub(/[][(){}.^$*+?|\\]/, "\\\\&", k);
                 pat = "^\"" k "\"[[:space:]]*=";
                 if ($0 ~ pat) { found=1 }
               }
             }
             END{ exit(found?0:1) }' "$CONFIG_FILE"; then
      # Replace existing line
      awk -v key="$original" -v line="$arr_line" '
        BEGIN{insec=0}
        /^\[mirrors\]/{insec=1}
        /^[[]/{if ($0!~/^\[mirrors\]/) insec=0}
        {
          if (insec){
            k=key; gsub(/[][(){}.^$*+?|\\]/, "\\\\&", k);
            pat = "^\"" k "\"[[:space:]]*=";
            if ($0 ~ pat) { print line; next }
          }
          print $0;
        }
      ' "$CONFIG_FILE" >"$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    else
      # Append within [mirrors]
      awk -v line="$arr_line" '
        BEGIN{insec=0}
        {
          print $0;
          if ($0 ~ /^\[mirrors\]/) {
            # Insert line after header
            print line;
          }
        }
      ' "$CONFIG_FILE" >"$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    fi
  fi
}

# Apply PyPI mirror selection
if [[ -n "$PIPY_CHOICE" ]]; then
  case "$PIPY_CHOICE" in
    tuna)
      PIPY_INDEX_URL="https://pypi.tuna.tsinghua.edu.cn/simple"
      PIPY_FILES_HOST="https://pypi.tuna.tsinghua.edu.cn"
      ;;
    aliyun)
      PIPY_INDEX_URL="https://mirrors.aliyun.com/pypi/simple"
      PIPY_FILES_HOST="https://mirrors.aliyun.com/pypi"
      ;;
    official)
      PIPY_INDEX_URL=""
      PIPY_FILES_HOST=""
      ;;
  esac

  # Set/clear [pypi-config].index-url
  set_pypi_index_url "$PIPY_INDEX_URL"

  # Update mirrors for PyPI resolving and downloads
  if [[ -n "${PIPY_FILES_HOST}" ]]; then
    set_mirror_mapping "https://pypi.org/simple" "$PIPY_INDEX_URL" "https://pypi.org/simple"
    set_mirror_mapping "https://files.pythonhosted.org" "$PIPY_FILES_HOST" "https://files.pythonhosted.org"
  else
    # Remove the mirrors lines
    set_mirror_mapping "https://pypi.org/simple"
    set_mirror_mapping "https://files.pythonhosted.org"
  fi
fi

# Apply conda-forge mirror selection
if [[ -n "$CF_CHOICE" ]]; then
  case "$CF_CHOICE" in
    tuna)
      CF_MIRROR="https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud/conda-forge"
      ;;
    aliyun)
      CF_MIRROR="https://mirrors.aliyun.com/anaconda/cloud/conda-forge"
      ;;
    official)
      CF_MIRROR=""
      ;;
  esac

  if [[ -n "$CF_MIRROR" ]]; then
    set_mirror_mapping "https://conda.anaconda.org/conda-forge" "$CF_MIRROR" "https://conda.anaconda.org/conda-forge"
  else
    set_mirror_mapping "https://conda.anaconda.org/conda-forge"
  fi
fi

echo "Updated Pixi config at: $CONFIG_FILE"
if [[ -n "$PIPY_CHOICE" ]]; then
  echo "  PyPI mirror: $PIPY_CHOICE"
fi
if [[ -n "$CF_CHOICE" ]]; then
  echo "  conda-forge mirror: $CF_CHOICE"
fi
