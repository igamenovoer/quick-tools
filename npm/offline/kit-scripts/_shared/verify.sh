#!/usr/bin/env sh
# Usage:
#   sh verify.sh --platform linux_x64
#   sh verify.sh --platform mac_arm64
# Notes:
#   - Checks required files and checksum integrity only.
#   - Does not install or modify system state.
set -eu

platform=""
die() { echo "verify: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
    case "$1" in
        --platform) platform="${2:-}"; shift 2 ;;
        -h|--help)
            cat <<EOF
Usage: verify.sh --platform <id>
EOF
            exit 0
            ;;
        *) die "unknown arg: $1" ;;
    esac
done

[ -n "$platform" ] || die "--platform is required"

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
kit_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)

[ -d "$kit_root/payloads/$platform/node" ] || die "missing platform payload: $platform"
[ -f "$kit_root/payloads/$platform/node/SHASUMS256.txt" ] || die "missing SHASUMS256.txt"
[ -f "$kit_root/payloads/$platform/pnpm/pnpm" ] || [ -f "$kit_root/payloads/$platform/pnpm/pnpm.exe" ] || die "missing pnpm payload"
[ -f "$kit_root/payloads/common/tools/package.json" ] || die "missing tools package.json"
[ -f "$kit_root/payloads/common/tools/pnpm-lock.yaml" ] || die "missing tools lockfile"
[ -d "$kit_root/payloads/common/pnpm-store" ] || die "missing pnpm-store"

if command -v sha256sum >/dev/null 2>&1; then
    (cd "$kit_root" && sha256sum -c checksums.sha256) >/dev/null
elif command -v shasum >/dev/null 2>&1; then
    (cd "$kit_root" && shasum -a 256 -c checksums.sha256) >/dev/null
else
    die "need sha256sum or shasum for verification"
fi

echo "OK" >&2
