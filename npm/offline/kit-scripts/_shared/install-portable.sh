#!/usr/bin/env sh
set -eu

platform=""
verify_only=0
run_scripts=0
force=0

die() { echo "install-portable: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
    case "$1" in
        --platform) platform="${2:-}"; shift 2 ;;
        --verify-only) verify_only=1; shift ;;
        --run-scripts) run_scripts=1; shift ;;
        --force) force=1; shift ;;
        -h|--help)
            cat <<EOF
Usage: install-portable.sh --platform <id> [--verify-only] [--run-scripts] [--force]
EOF
            exit 0
            ;;
        *) die "unknown arg: $1" ;;
    esac
done

[ -n "$platform" ] || die "--platform is required"

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
kit_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)

payload_node="$kit_root/payloads/$platform/node"
payload_pnpm="$kit_root/payloads/$platform/pnpm"
payload_tools="$kit_root/payloads/common/tools"
payload_store="$kit_root/payloads/common/pnpm-store"

[ -d "$payload_node" ] || die "missing: $payload_node"
[ -d "$payload_pnpm" ] || die "missing: $payload_pnpm"
[ -d "$payload_tools" ] || die "missing: $payload_tools"
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

prefix="$kit_root/installed/$platform"
node_dir="$prefix/node"
pnpm_home="$prefix/pnpm-bin"
npm_prefix="$prefix/npm-prefix"
tools_dir="$prefix/tools"

if [ "$force" -eq 1 ] && [ -d "$prefix" ]; then
    rm -rf "$prefix"
fi

mkdir -p "$node_dir" "$pnpm_home" "$npm_prefix" "$tools_dir"

echo "Installing Node (portable) to: $node_dir" >&2
tar -xJf "$node_portable" -C "$node_dir" --strip-components=1

echo "Installing pnpm to: $pnpm_home" >&2
cp -f "$pnpm_bin" "$pnpm_home/pnpm"
chmod +x "$pnpm_home/pnpm"

echo "Installing tools (offline) to: $tools_dir" >&2
cp -f "$payload_tools/package.json" "$tools_dir/package.json"
cp -f "$payload_tools/pnpm-lock.yaml" "$tools_dir/pnpm-lock.yaml"

install_args="install --offline --frozen-lockfile --store-dir \"$payload_store\""
if [ "$run_scripts" -ne 1 ]; then
    install_args="$install_args --ignore-scripts"
fi

(cd "$tools_dir" && sh -c "\"$pnpm_home/pnpm\" $install_args") >/dev/null

echo "" >&2
echo "Portable install complete." >&2
echo "Activate for current session:" >&2
echo "  . \"$kit_root/scripts/$platform/activate.sh\" --kit-root \"$kit_root\"" >&2
