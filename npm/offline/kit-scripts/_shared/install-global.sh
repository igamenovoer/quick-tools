#!/usr/bin/env sh
set -eu

platform=""
verify_only=0
run_scripts=0
force=0

die() { echo "install-global: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
    case "$1" in
        --platform) platform="${2:-}"; shift 2 ;;
        --verify-only) verify_only=1; shift ;;
        --run-scripts) run_scripts=1; shift ;;
        --force) force=1; shift ;;
        -h|--help)
            cat <<EOF
Usage: install-global.sh --platform <id> [--verify-only] [--run-scripts] [--force]
EOF
            exit 0
            ;;
        *) die "unknown arg: $1" ;;
    esac
done

[ -n "$platform" ] || die "--platform is required"

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
kit_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)

if [ "$(id -u)" -ne 0 ]; then
    die "global install requires root (sudo)."
fi

payload_node="$kit_root/payloads/$platform/node"
payload_pnpm="$kit_root/payloads/$platform/pnpm"
payload_tools="$kit_root/payloads/common/tools"
payload_store="$kit_root/payloads/common/pnpm-store"
[ -d "$payload_store" ] || die "missing: $payload_store"

node_portable=$(ls -1 "$payload_node"/node-portable* 2>/dev/null | head -n 1 || true)
[ -n "$node_portable" ] || die "missing node-portable* under $payload_node"

pnpm_bin="$payload_pnpm/pnpm"
[ -f "$pnpm_bin" ] || die "missing: $pnpm_bin"

if command -v sha256sum >/dev/null 2>&1; then
    (cd "$kit_root" && sha256sum -c checksums.sha256) >/dev/null
elif command -v shasum >/dev/null 2>&1; then
    (cd "$kit_root" && shasum -a 256 -c checksums.sha256) >/dev/null
else
    die "need sha256sum or shasum for verification"
fi

if [ "$verify_only" -eq 1 ]; then
    echo "OK" >&2
    exit 0
fi

if [ "${platform#mac_}" != "$platform" ] && [ -f "$payload_node/node-installer.pkg" ]; then
    echo "Installing Node.js globally via pkg installer..." >&2
    installer -pkg "$payload_node/node-installer.pkg" -target /
else
    echo "Installing Node.js globally into /usr/local ..." >&2
    tar -xJf "$node_portable" -C /usr/local --strip-components=1
fi

echo "Installing pnpm into /usr/local/bin/pnpm ..." >&2
install -m 0755 "$pnpm_bin" /usr/local/bin/pnpm

system_root="/opt/npm-offline-kit"
tools_dir="$system_root/tools"

if [ "$force" -eq 1 ] && [ -d "$system_root" ]; then
    rm -rf "$system_root"
fi

mkdir -p "$tools_dir"
cp -f "$payload_tools/package.json" "$tools_dir/package.json"
cp -f "$payload_tools/pnpm-lock.yaml" "$tools_dir/pnpm-lock.yaml"

install_args="install --offline --frozen-lockfile --store-dir \"$payload_store\""
if [ "$run_scripts" -ne 1 ]; then
    install_args="$install_args --ignore-scripts"
fi

(cd "$tools_dir" && sh -c "/usr/local/bin/pnpm $install_args") >/dev/null

echo "Linking tool entrypoints into /usr/local/bin ..." >&2
if [ -d "$tools_dir/node_modules/.bin" ]; then
    for f in "$tools_dir/node_modules/.bin/"*; do
        [ -e "$f" ] || continue
        name=$(basename "$f")
        target="/usr/local/bin/$name"
        if [ -e "$target" ] && [ "$force" -ne 1 ]; then
            continue
        fi
        ln -sf "$f" "$target"
    done
fi

echo "Global install complete." >&2
