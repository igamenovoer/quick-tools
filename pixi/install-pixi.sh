#!/bin/sh
set -eu

usage() {
    cat <<'EOF'
Install Pixi (Linux/macOS).

Online (default): runs Pixi’s official installer script.
Offline: provide --package-path <downloaded-archive> (not extracted) to install without downloading the official script.

Usage:
    ./install-pixi.sh [--pixi-home <dir>] [--pixi-version <ver>] [--no-path-update]
    ./install-pixi.sh --package-path <archive> [--pixi-home <dir>] [--no-path-update]

Options:
    --package-path <path>      Offline install from a downloaded archive (.tar.gz/.tgz/.zip) or raw binary.
    --pixi-home <dir>          Pixi home directory (default: $HOME/.pixi).
    --pixi-version <ver>       Version for online install (default: latest).
    --pixi-repo-url <url>      Repo URL for online install (default: https://github.com/prefix-dev/pixi).
    --install-script-url <url> Official install script URL (default: https://pixi.sh/install.sh).
    --no-path-update           Do not update shell PATH config.
    -h, --help                 Show this help.
EOF
}

mask_credentials() {
    # Replace username:password@ pattern with ***:***@
    echo "${1}" | sed -E 's|://[^:@/]+:[^@/]+@|://***:***@|g'
}

expand_tilde() {
    case "${1}" in
        '~'|'~'/*) printf '%s\n' "${HOME-}${1#\~}" ;;
        *) printf '%s\n' "${1}" ;;
    esac
}

update_shell() {
    update_shell_file_path="$1"
    update_shell_line="$2"

    if [ ! -f "$update_shell_file_path" ]; then
        mkdir -p "$(dirname "$update_shell_file_path")"
        touch "$update_shell_file_path"
    fi

    if ! grep -Fxq "$update_shell_line" "$update_shell_file_path"; then
        printf "Updating '%s'\n" "$update_shell_file_path"
        printf '\n%s\n' "$update_shell_line" >>"$update_shell_file_path"
        echo "Please restart or source your shell."
    fi
}

add_to_path() {
    pixi_bin_dir="$1"

    if [ -n "${PIXI_NO_PATH_UPDATE:-}" ]; then
        echo "No path update because PIXI_NO_PATH_UPDATE is set"
        return 0
    fi

    case "$(basename "${SHELL-}")" in
        bash)
            # Default to bashrc as that is used in non login shells instead of the profile.
            update_shell "${HOME}/.bashrc" "export PATH=\"${pixi_bin_dir}:\$PATH\""
            ;;
        fish)
            # Use 'set -gx PATH' for compatibility with Fish < 3.2.0 (which lacks fish_add_path)
            update_shell "${HOME}/.config/fish/config.fish" "set -gx PATH \"${pixi_bin_dir}\" \$PATH"
            ;;
        zsh)
            update_shell "${HOME}/.zshrc" "export PATH=\"${pixi_bin_dir}:\$PATH\""
            ;;
        tcsh)
            update_shell "${HOME}/.tcshrc" "set path = ( ${pixi_bin_dir} \$path )"
            ;;
        '')
            echo "warn: Could not detect shell type." >&2
            echo "      Please permanently add '${pixi_bin_dir}' to your \$PATH to enable the 'pixi' command." >&2
            ;;
        *)
            echo "warn: Could not update shell $(basename "${SHELL}")" >&2
            echo "      Please permanently add '${pixi_bin_dir}' to your \$PATH to enable the 'pixi' command." >&2
            ;;
    esac
}

extract_pixi_from_archive() {
    archive_path="$1"
    pixi_bin_dir="$2"

    mkdir -p "$pixi_bin_dir"

    detect_archive_kind() {
        detect_path="$1"

        # Read first 4 bytes and format as hex (no spaces/newlines).
        magic4="$(dd if="$detect_path" bs=4 count=1 2>/dev/null | od -An -tx1 | tr -d ' \n')"
        case "$magic4" in
            504b0304*|504b0506*|504b0708*) echo "zip"; return 0 ;; # PK..
            1f8b08*) echo "tar.gz"; return 0 ;;                   # gzip
            4d5a*) echo "exe"; return 0 ;;                        # MZ
        esac
        echo "raw"
        return 0
    }

    case "$archive_path" in
        *.tar.gz|*.tgz) archive_kind="tar.gz" ;;
        *.zip) archive_kind="zip" ;;
        *.exe) archive_kind="exe" ;;
        *) archive_kind="$(detect_archive_kind "$archive_path")" ;;
    esac

    case "$archive_kind" in
        tar.gz)
            if ! command -v tar >/dev/null 2>&1; then
                echo "error: 'tar' is required to extract ${archive_path}" >&2
                return 1
            fi
            temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/.pixi_extract.XXXXXXXX")"
            tar -xzf "$archive_path" -C "$temp_dir"

            if [ -f "$temp_dir/pixi" ]; then
                mv "$temp_dir/pixi" "${pixi_bin_dir}/"
            else
                mv "$(find "$temp_dir" -type f -name pixi | head -n 1)" "${pixi_bin_dir}/"
            fi

            chmod +x "${pixi_bin_dir}/pixi"
            rm -rf "$temp_dir"
            ;;
        zip)
            if command -v unzip >/dev/null 2>&1; then
                unzip -o "$archive_path" -d "$pixi_bin_dir" >/dev/null
            elif command -v bsdtar >/dev/null 2>&1; then
                bsdtar -xf "$archive_path" -C "$pixi_bin_dir"
            else
                echo "error: need either 'unzip' or 'bsdtar' to extract ${archive_path}" >&2
                return 1
            fi

            if [ ! -f "${pixi_bin_dir}/pixi" ]; then
                found="$(find "$pixi_bin_dir" -type f -name pixi | head -n 1 || true)"
                if [ -n "$found" ]; then
                    mv "$found" "${pixi_bin_dir}/pixi"
                fi
            fi

            chmod +x "${pixi_bin_dir}/pixi" 2>/dev/null || true
            ;;
        exe)
            echo "error: '${archive_path}' looks like a Windows build (.exe)." >&2
            echo "       For Linux/macOS, download the appropriate .tar.gz (or a raw 'pixi' binary) instead." >&2
            return 1
            ;;
        *)
            # Mimic the official script's fallback behavior when it can't use an archive format:
            # treat the downloaded file as the pixi binary itself.
            cp -f "$archive_path" "${pixi_bin_dir}/pixi"
            chmod +x "${pixi_bin_dir}/pixi" 2>/dev/null || true
            ;;
    esac

    if [ ! -f "${pixi_bin_dir}/pixi" ]; then
        if [ -n "$(find "$pixi_bin_dir" -type f -name 'pixi.exe' -print -quit 2>/dev/null)" ]; then
            echo "error: extracted a Windows binary (pixi.exe). Download the Linux/macOS archive instead." >&2
            return 1
        fi
        echo "error: could not locate extracted 'pixi' binary in ${pixi_bin_dir}" >&2
        return 1
    fi
}

PACKAGE_PATH=""
PIXI_VERSION="${PIXI_VERSION:-latest}"
PIXI_HOME="${PIXI_HOME:-$HOME/.pixi}"
PIXI_REPO_URL="${PIXI_REPOURL:-https://github.com/prefix-dev/pixi}"
INSTALL_SCRIPT_URL="https://pixi.sh/install.sh"
NO_PATH_UPDATE=0

while [ $# -gt 0 ]; do
    case "$1" in
        --package-path)
            PACKAGE_PATH="${2:-}"; shift 2 ;;
        --pixi-home)
            PIXI_HOME="${2:-}"; shift 2 ;;
        --pixi-version)
            PIXI_VERSION="${2:-}"; shift 2 ;;
        --pixi-repo-url)
            PIXI_REPO_URL="${2:-}"; shift 2 ;;
        --install-script-url)
            INSTALL_SCRIPT_URL="${2:-}"; shift 2 ;;
        --no-path-update)
            NO_PATH_UPDATE=1; shift 1 ;;
        -h|--help)
            usage; exit 0 ;;
        *)
            echo "error: unknown argument: $1" >&2
            usage
            exit 2 ;;
    esac
done

PIXI_HOME="$(expand_tilde "$PIXI_HOME")"
PIXI_BIN_DIR="${PIXI_BIN_DIR:-${PIXI_HOME}/bin}"

if [ "$NO_PATH_UPDATE" -eq 1 ]; then
    export PIXI_NO_PATH_UPDATE=1
fi

if [ -z "$PACKAGE_PATH" ]; then
    # Online install via official script (default).
    export PIXI_VERSION="$PIXI_VERSION"
    export PIXI_HOME="$PIXI_HOME"
    export PIXI_BIN_DIR="$PIXI_BIN_DIR"
    export PIXI_REPOURL="${PIXI_REPO_URL%/}"

    echo "Running official Pixi installer script from: $(mask_credentials "$INSTALL_SCRIPT_URL")"

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$INSTALL_SCRIPT_URL" | sh
        exit 0
    fi
    if command -v wget >/dev/null 2>&1; then
        wget -qO- "$INSTALL_SCRIPT_URL" | sh
        exit 0
    fi

    echo "error: you need either 'curl' or 'wget' installed for this script." >&2
    exit 1
fi

PACKAGE_PATH="$(expand_tilde "$PACKAGE_PATH")"
if [ ! -f "$PACKAGE_PATH" ]; then
    echo "error: --package-path does not exist or is not a file: ${PACKAGE_PATH}" >&2
    exit 1
fi

echo "Installing Pixi from archive: ${PACKAGE_PATH}"
echo "Extracting into: ${PIXI_BIN_DIR}"
extract_pixi_from_archive "$PACKAGE_PATH" "$PIXI_BIN_DIR"
echo "The 'pixi' binary is installed into '${PIXI_BIN_DIR}'"

add_to_path "$PIXI_BIN_DIR"
