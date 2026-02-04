# Pixi Tools

Scripts for installing and managing Pixi.

## Contents

- `install-pixi.ps1`: PowerShell script to install Pixi on Windows.
  - Online (default): runs Pixi’s official installer script.
  - Offline: `-PackagePath <path-to-downloaded-zip>` installs from a pre-downloaded release archive (not extracted).
- `install-pixi.sh`: Shell script to install Pixi on Linux/macOS.
  - Online (default): runs Pixi’s official installer script.
  - Offline: `--package-path <path-to-downloaded-archive>` installs from a pre-downloaded archive (not extracted; extension optional) or a raw `pixi` binary.
