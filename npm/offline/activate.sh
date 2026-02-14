#!/usr/bin/env sh
set -eu

print_help() {
    cat <<'EOF'
Usage:
  . ./activate.sh [--kit-root PATH] [--platform ID] [--quiet]
  ./activate.sh --kit-root PATH --persist [--platform ID] [--rc FILE] [--quiet]
  ./activate.sh --kit-root PATH --unpersist [--rc FILE] [--quiet]

Notes:
  - To affect the current shell session, this script must be sourced:
      . ./activate.sh --kit-root /path/to/kit
  - --persist appends a small block to ~/.bashrc or ~/.zshrc (or --rc FILE).
EOF
}

is_sourced() {
    (return 0 2>/dev/null)
}

die() {
    echo "activate.sh: $*" >&2
    if is_sourced; then
        return 1
    fi
    exit 1
}

abs_dirname() {
    script_path=$1
    script_dir=$(CDPATH= cd -- "$(dirname -- "$script_path")" && pwd -P)
    echo "$script_dir"
}

find_kit_root_upwards() {
    start_dir=$1
    current_dir=$start_dir

    while :; do
        if [ -f "$current_dir/config.toml" ] || [ -f "$current_dir/config.yaml" ]; then
            echo "$current_dir"
            return 0
        fi

        if [ -d "$current_dir/payloads" ] || [ -d "$current_dir/installed" ]; then
            echo "$current_dir"
            return 0
        fi

        parent_dir=$(CDPATH= cd -- "$current_dir/.." && pwd -P)
        if [ "$parent_dir" = "$current_dir" ]; then
            return 1
        fi
        current_dir=$parent_dir
    done
}

detect_os() {
    uname_s=$(uname -s 2>/dev/null || echo unknown)
    case "$uname_s" in
        Linux) echo linux ;;
        Darwin) echo darwin ;;
        *) echo unknown ;;
    esac
}

detect_arch() {
    uname_m=$(uname -m 2>/dev/null || echo unknown)
    case "$uname_m" in
        x86_64|amd64) echo x64 ;;
        aarch64|arm64) echo arm64 ;;
        *) echo unknown ;;
    esac
}

normalize_platform_id() {
    os=$1
    arch=$2
    case "$os" in
        linux)
            echo "linux_${arch}"
            return 0
            ;;
        darwin)
            echo "mac_${arch}"
            return 0
            ;;
        *)
            die "unsupported OS for this script: $os"
            ;;
    esac
}

path_prepend() {
    dir=$1
    case ":$PATH:" in
        *":$dir:"*) ;;
        *) PATH="$dir:$PATH" ;;
    esac
}

choose_rc_file() {
    if [ -n "${rc_override:-}" ]; then
        echo "$rc_override"
        return 0
    fi

    shell_basename=$(basename "${SHELL:-sh}" 2>/dev/null || echo sh)
    case "$shell_basename" in
        zsh) echo "$HOME/.zshrc" ;;
        bash) echo "$HOME/.bashrc" ;;
        *) echo "$HOME/.profile" ;;
    esac
}

persist_block() {
    rc_file=$1
    activate_path=$2

    marker_begin="# >>> npm-offline-kit >>>"
    marker_end="# <<< npm-offline-kit <<<"

    mkdir -p "$(dirname "$rc_file")" 2>/dev/null || true
    if [ ! -f "$rc_file" ]; then
        : >"$rc_file"
    fi

    tmp_file="$rc_file.tmp.$$"

    awk -v begin="$marker_begin" -v end="$marker_end" '
        $0 == begin { inblock=1; next }
        $0 == end { inblock=0; next }
        inblock != 1 { print }
    ' "$rc_file" >"$tmp_file"

    {
        echo "$marker_begin"
        echo "# Added by npm-offline portable-only activation"
        echo ". \"$activate_path\" --kit-root \"$kit_root\" --quiet"
        echo "$marker_end"
    } >>"$tmp_file"

    mv "$tmp_file" "$rc_file"
}

unpersist_block() {
    rc_file=$1
    marker_begin="# >>> npm-offline-kit >>>"
    marker_end="# <<< npm-offline-kit <<<"

    if [ ! -f "$rc_file" ]; then
        return 0
    fi

    tmp_file="$rc_file.tmp.$$"
    awk -v begin="$marker_begin" -v end="$marker_end" '
        $0 == begin { inblock=1; next }
        $0 == end { inblock=0; next }
        inblock != 1 { print }
    ' "$rc_file" >"$tmp_file"
    mv "$tmp_file" "$rc_file"
}

kit_root=""
platform_id=""
quiet=0
persist=0
unpersist=0
rc_override=""

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)
            print_help
            if is_sourced; then
                return 0
            fi
            exit 0
            ;;
        --kit-root)
            [ $# -ge 2 ] || die "--kit-root requires a value"
            kit_root=$2
            shift 2
            ;;
        --platform)
            [ $# -ge 2 ] || die "--platform requires a value"
            platform_id=$2
            shift 2
            ;;
        --rc)
            [ $# -ge 2 ] || die "--rc requires a value"
            rc_override=$2
            shift 2
            ;;
        --persist)
            persist=1
            shift 1
            ;;
        --unpersist)
            unpersist=1
            shift 1
            ;;
        --quiet)
            quiet=1
            shift 1
            ;;
        *)
            die "unknown argument: $1"
            ;;
    esac
done

script_dir=$(abs_dirname "${0}")

if [ -z "$kit_root" ]; then
    kit_root=$(find_kit_root_upwards "$script_dir" 2>/dev/null || true)
    if [ -z "$kit_root" ]; then
        die "could not infer --kit-root; pass --kit-root"
    fi
fi

kit_root=$(CDPATH= cd -- "$kit_root" && pwd -P)

if [ "$unpersist" -eq 1 ]; then
    rc_file=$(choose_rc_file)
    unpersist_block "$rc_file"
    if [ "$quiet" -ne 1 ]; then
        echo "Removed persisted activation from: $rc_file" >&2
    fi
    if is_sourced; then
        return 0
    fi
    exit 0
fi

if [ -z "$platform_id" ]; then
    dir_platform=$(basename "$script_dir" 2>/dev/null || true)
    case "$dir_platform" in
        linux_x64|linux_arm64|mac_arm64|mac_x64)
            platform_id=$dir_platform
            ;;
        *)
            os=$(detect_os)
            arch=$(detect_arch)
            platform_id=$(normalize_platform_id "$os" "$arch")
            ;;
    esac
fi

prefix="$kit_root/installed/$platform_id"

node_bin_dir=""
if [ -x "$prefix/node/bin/node" ]; then
    node_bin_dir="$prefix/node/bin"
elif [ -x "$prefix/node/node" ]; then
    node_bin_dir="$prefix/node"
else
    if [ "$persist" -ne 1 ]; then
        die "Node not found under '$prefix/node' (expected node/bin/node or node/node)"
    fi
fi

npm_prefix="$prefix/npm-prefix"
pnpm_home="$prefix/pnpm-bin"
tools_bin="$prefix/tools/node_modules/.bin"
tool_bin="$prefix/bin"

if is_sourced && [ "$persist" -ne 1 ]; then
    export NPM_OFFLINE_KIT_ROOT="$kit_root"
    export NPM_OFFLINE_PLATFORM="$platform_id"
    export NPM_CONFIG_PREFIX="$npm_prefix"
    export PNPM_HOME="$pnpm_home"

    if [ -n "$node_bin_dir" ]; then
        path_prepend "$node_bin_dir"
    fi
    path_prepend "$pnpm_home"
    path_prepend "$npm_prefix/bin"
    path_prepend "$tools_bin"
    path_prepend "$tool_bin"

    export PATH

    if [ "$quiet" -ne 1 ]; then
        echo "Activated kit: $kit_root" >&2
        echo "Platform: $platform_id" >&2
    fi

    return 0
fi

if [ "$persist" -eq 1 ]; then
    rc_file=$(choose_rc_file)
    activate_path="$script_dir/$(basename "$0")"

    persist_block "$rc_file" "$activate_path"
    if [ "$quiet" -ne 1 ]; then
        echo "Persisted activation into: $rc_file" >&2
        echo "Open a new shell, or run: . \"$activate_path\" --kit-root \"$kit_root\"" >&2
    fi
    exit 0
fi

cat >&2 <<EOF
This script must be sourced to affect the current shell.

Run:
  . "$script_dir/$(basename "$0")" --kit-root "$kit_root"
EOF
exit 2
