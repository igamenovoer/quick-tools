# npm-offline-kit (portable + global)

This folder contains scripts for building and using an offline Node.js + global npm-tools “kit” intended for air-gapped hosts.

## What “portable-only” means

Portable-only mode installs everything into a kit-controlled directory (a “prefix”) and exposes the toolchain by setting environment variables and `PATH`.

- No system-wide install locations (no `/usr/local`, no `Program Files`)
- No admin/root required (by default)
- To “use it like a normal npm environment”, you activate the kit (sets `PATH`, `NPM_CONFIG_PREFIX`, etc.)
- Optional: persist activation by writing a small block into shell startup config (`~/.bashrc`/`~/.zshrc`) or Windows user environment variables

## Global install: what it means

Global mode installs:

- Node.js into OS system locations (requires `sudo` / Administrator)
- pnpm into system locations
- the curated toolset into a system directory and links tool entrypoints into standard `PATH` locations

This is intentionally more invasive; prefer portable mode when admin/root is not desirable.

## End-to-end usage

### 1) Create a kit on the WAN host

Start from an example config:

- `quick-tools/npm/offline/config.example.toml`

Build:

```powershell
pwsh quick-tools/npm/offline/build-kit.ps1 `
  -ConfigPath quick-tools/npm/offline/config.example.toml `
  -OutputDir dist/npm-offline-kit `
  -Force
```

This produces a directory like `dist/npm-offline-kit/` containing `payloads/` and `scripts/<platform-id>/...`.

### 2) Copy the kit directory to the air-gapped host

Copy the entire kit directory (do not omit `payloads/`).

### 3) Verify kit integrity (offline)

POSIX:

```sh
sh /path/to/kit/scripts/<platform-id>/verify.sh
```

Windows:

```bat
call C:\path\to\kit\scripts\<platform-id>\verify.bat
```

### 4) Install (offline)

Portable install (recommended):

- POSIX: `sh /path/to/kit/scripts/<platform-id>/install-portable.sh`
- Windows: `call C:\path\to\kit\scripts\<platform-id>\install-portable.bat`

Global install (requires admin/root):

- POSIX: `sudo sh /path/to/kit/scripts/<platform-id>/install-global.sh`
- Windows: run `install-global.bat` from an elevated cmd.exe / PowerShell

## Activation scripts

### POSIX (bash/zsh)

For the current shell session (recommended):

```sh
. /path/to/kit/scripts/<platform-id>/activate.sh --kit-root /path/to/kit
```

Persist for future shells:

```sh
/path/to/kit/scripts/<platform-id>/activate.sh --kit-root /path/to/kit --persist
```

Remove persisted activation:

```sh
/path/to/kit/scripts/<platform-id>/activate.sh --kit-root /path/to/kit --unpersist
```

### Windows

cmd.exe (current session):

```bat
call C:\path\to\kit\scripts\<platform-id>\activate.bat --kit-root C:\path\to\kit
```

Persist for the current user (requires PowerShell):

```bat
call C:\path\to\kit\scripts\<platform-id>\activate.bat --kit-root C:\path\to\kit --persist
```

PowerShell (current session):

```powershell
. C:\path\to\kit\scripts\<platform-id>\activate.ps1 -KitRoot C:\path\to\kit
```

Persist for the current user:

```powershell
& C:\path\to\kit\scripts\<platform-id>\activate.ps1 -KitRoot C:\path\to\kit -Persist
```

## Environment variables set

- `NPM_OFFLINE_KIT_ROOT`: kit root directory
- `NPM_OFFLINE_PLATFORM`: platform id (example: `win32_x64`, `linux_x64`, `linux_arm64`, `mac_arm64`, `mac_x64`)
- `NPM_CONFIG_PREFIX`: npm global prefix (portable) inside the kit
- `PNPM_HOME`: pnpm global bin directory (portable) inside the kit

The scripts also prepend the relevant kit directories to `PATH`.

## Notes / limitations

- Packages that require native compilation toolchains or that download binaries in postinstall may not work offline unless those artifacts are also provided.
- Portable mode expects you to either source `activate.sh` (POSIX) or `call activate.bat` / dot-source `activate.ps1` (Windows) before using tools in a new shell.
