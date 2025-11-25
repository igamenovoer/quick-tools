# VS Code Server Cache File Placement for Air-Gapped Remote-SSH

This document describes how to set up VS Code Remote-SSH in an air-gapped environment by pre-placing server files where VS Code expects to find them, avoiding download failures.

## The Problem

When connecting via Remote-SSH in an air-gapped environment (no internet access), VS Code attempts to:
1. Download VS Code Server on the remote host (fails - no internet)
2. Fall back to downloading locally and transferring via SSH (fails - local also has no internet)

This results in the error:
```
[LocalDownloadFailed]: Error: LocalDownloadFailed (Failed to download VS Code Server (Failed to fetch))
```

## The Solution: Cache File Detection

**For VS Code version 1.82.0 and later**, the Remote-SSH extension checks for pre-existing server files before attempting to download. If it finds specific files in the expected locations with correct naming, it will **skip the download** and use the cached files.

### Key Discovery

VS Code Remote-SSH looks for these specific files on the **remote server** in `~/.vscode-server/`:

1. **`vscode-cli-${COMMIT}.tar.gz.done`** - A marker file indicating the CLI is downloaded
2. **`vscode-server.tar.gz`** - The server tarball ready for extraction
3. **`cli/servers/Stable-${COMMIT}/server/`** - The already-extracted server (optional but recommended)

Where `${COMMIT}` is your VS Code client's commit hash (find it in Help → About).

## Implementation Steps

### 1. Get Your VS Code Commit Hash

In VS Code:
- Open **Help** → **About**
- Find **Commit**: `1e3c50d64110be466c0b4a45222e81d2c9352888` (example)

### 2. Download Required Files (on a machine with internet)

Download from Microsoft's update servers:

```bash
COMMIT="1e3c50d64110be466c0b4a45222e81d2c9352888"

# Download VS Code Server (70MB)
wget "https://update.code.visualstudio.com/commit:${COMMIT}/server-linux-x64/stable" \
  -O "vscode-server-linux-x64-${COMMIT}.tar.gz"

# Download VS Code CLI (10MB)
wget "https://update.code.visualstudio.com/commit:${COMMIT}/cli-alpine-x64/stable" \
  -O "vscode-cli-alpine-x64-${COMMIT}.tar.gz"
```

### 3. Transfer Files to Air-Gapped Environment

Copy both tarballs to your air-gapped environment's package directory.

### 4. Pre-Place Files on Remote Server

On the remote server (where you'll SSH into):

```bash
COMMIT="1e3c50d64110be466c0b4a45222e81d2c9352888"
VSCODE_SERVER_DIR="$HOME/.vscode-server"

# Create directory structure
mkdir -p "${VSCODE_SERVER_DIR}"
mkdir -p "${VSCODE_SERVER_DIR}/cli/servers/Stable-${COMMIT}/server"
mkdir -p "${VSCODE_SERVER_DIR}/extensions"
mkdir -p "${VSCODE_SERVER_DIR}/data/Machine"

# Copy the CLI tarball
cp "vscode-cli-alpine-x64-${COMMIT}.tar.gz" \
   "${VSCODE_SERVER_DIR}/vscode-cli-${COMMIT}.tar.gz"

# Create the .done marker file
cp "${VSCODE_SERVER_DIR}/vscode-cli-${COMMIT}.tar.gz" \
   "${VSCODE_SERVER_DIR}/vscode-cli-${COMMIT}.tar.gz.done"

# Copy the server tarball with the expected name
cp "vscode-server-linux-x64-${COMMIT}.tar.gz" \
   "${VSCODE_SERVER_DIR}/vscode-server.tar.gz"

# Extract the server (recommended)
tar -xzf "vscode-server-linux-x64-${COMMIT}.tar.gz" \
    -C "${VSCODE_SERVER_DIR}/cli/servers/Stable-${COMMIT}/server" \
    --strip-components=1

# Create configuration files
echo '{}' > "${VSCODE_SERVER_DIR}/data/Machine/settings.json"
touch "${VSCODE_SERVER_DIR}/cli/servers/Stable-${COMMIT}/server/.ready"
```

### 5. Final Directory Structure

Your `~/.vscode-server/` should look like this:

```
~/.vscode-server/
├── vscode-cli-1e3c50d64110be466c0b4a45222e81d2c9352888.tar.gz       (10MB)
├── vscode-cli-1e3c50d64110be466c0b4a45222e81d2c9352888.tar.gz.done  (10MB, marker file)
├── vscode-server.tar.gz                                             (70MB)
├── cli/
│   └── servers/
│       └── Stable-1e3c50d64110be466c0b4a45222e81d2c9352888/
│           └── server/
│               ├── bin/
│               │   └── code-server
│               ├── node_modules/
│               ├── out/
│               ├── package.json
│               ├── product.json
│               └── .ready
├── data/
│   └── Machine/
│       └── settings.json
└── extensions/
```

### 6. Connect via Remote-SSH

Now when you connect via Remote-SSH:
1. Press `F1` → **Remote-SSH: Connect to Host...**
2. Select your remote host
3. VS Code will detect the pre-placed files and skip downloading
4. Connection should succeed immediately

## How VS Code Detects Cache Files

Based on research and testing, here's the detection logic:

1. **Check for `.done` marker**: VS Code looks for `vscode-cli-${COMMIT}.tar.gz.done`
   - If found: Assumes CLI is already downloaded
2. **Check for server tarball**: Looks for `vscode-server.tar.gz`
   - If found: Uses this for server installation instead of downloading
3. **Check for extracted server**: Looks for `cli/servers/Stable-${COMMIT}/server/`
   - If found and has `.ready` file: Skips extraction entirely

This cascade allows for maximum flexibility in offline deployments.

## Important Notes

### VS Code Version Matching

**Critical**: The commit hash MUST match your local VS Code version exactly. Mismatched versions will cause connection failures.

To check versions:
- **Local VS Code**: Help → About → Commit
- **Remote Server**: The commit hash in directory names

### File Naming is Strict

The Remote-SSH extension expects **exact filenames**:
- ✅ `vscode-cli-${COMMIT}.tar.gz.done` (note the `.done` suffix)
- ✅ `vscode-server.tar.gz` (generic name, not commit-specific)
- ❌ `vscode-server-linux-x64-${COMMIT}.tar.gz` (won't be detected)

### Distinction: code-server vs VS Code Server

**⚠️ Important**: Do NOT confuse these two different projects:

#### Microsoft VS Code Server
- **URL**: `https://update.code.visualstudio.com/`
- **Purpose**: Backend for Remote-SSH extension
- **File**: `vscode-server-linux-x64.tar.gz` (~70MB)
- **Use**: Remote development via SSH tunnel
- **Required**: YES, for this setup

#### Coder's code-server
- **URL**: `https://github.com/coder/code-server`
- **Purpose**: Run VS Code in a web browser
- **File**: `code-server-${VERSION}-linux-amd64.tar.gz` (~116MB)
- **Use**: Web-based VS Code IDE
- **Required**: NO, not needed for Remote-SSH

**Our setup uses Microsoft VS Code Server, NOT Coder's code-server.**

## Automation Script

For convenience, we created `install-vscode-server-on-remote.sh` which automates this process:

```bash
# On the remote server
bash install-vscode-server-on-remote.sh
```

The script:
- Checks for tarballs in `/pkgs-host/`
- Extracts to correct locations
- Creates all necessary files and directories
- Sets proper permissions
- Verifies the installation

## Troubleshooting

### Connection Still Fails

1. **Verify commit hash matches**:
   ```bash
   # Local VS Code
   Help → About → Commit

   # Remote server
   ls ~/.vscode-server/cli/servers/
   ```

2. **Check file permissions**:
   ```bash
   ls -la ~/.vscode-server/
   # All files should be owned by your user
   ```

3. **Verify .ready marker exists**:
   ```bash
   ls ~/.vscode-server/cli/servers/Stable-${COMMIT}/server/.ready
   ```

4. **Check VS Code logs**:
   - In VS Code: View → Output → Remote-SSH
   - Look for "Found existing installation" or download attempts

### Files Not Detected

If VS Code still tries to download:

1. **Double-check filename spelling** (especially the `.done` suffix)
2. **Ensure files are in the correct directory** (`~/.vscode-server/` not `~/.vscode/`)
3. **Verify tarball integrity**:
   ```bash
   tar -tzf vscode-server.tar.gz | head
   # Should list files, not show errors
   ```

## Performance Benefits

Pre-placing files offers several advantages:

1. **Fast Connection**: No download wait time (0 seconds vs 30+ seconds)
2. **Consistent**: Works reliably without internet dependency
3. **Bandwidth**: No network usage during connection
4. **Version Control**: Ensures specific VS Code versions are used

## References and Sources

This approach is documented in various Stack Overflow answers and GitHub issues:

- [How to install vscode-server offline (1.82.0+)](https://stackoverflow.com/questions/77068802/how-do-i-install-vscode-server-offline-on-a-server-for-vs-code-version-1-82-0-or)
- [VS Code Remote-SSH in air-gapped environments](https://stackoverflow.com/questions/56718453/using-remote-ssh-in-vscode-on-a-target-machine-that-only-allows-inbound-ssh-co)
- [LocalDownloadFailed error fix](https://stackoverflow.com/questions/79622709/vs-code-server-localdownloadfailed-error-localdownloadfailed-failed-to-down)
- [Remote-SSH troubleshooting guide](https://code.visualstudio.com/docs/remote/troubleshooting)
- [Remote Development Tips](https://code.visualstudio.com/blogs/2019/10/03/remote-ssh-tips-and-tricks)

## Version History

- **VS Code < 1.82.0**: Server installed to `~/.vscode-server/bin/${COMMIT}/`
- **VS Code ≥ 1.82.0**: Server installed to `~/.vscode-server/cli/servers/Stable-${COMMIT}/server/`

This document describes the **modern approach (1.82.0+)** which is what VS Code 1.106.2 uses.

## Summary

By understanding VS Code's cache detection mechanism and pre-placing files with correct naming:
- ✅ `vscode-cli-${COMMIT}.tar.gz.done` - CLI marker
- ✅ `vscode-server.tar.gz` - Server tarball
- ✅ `cli/servers/Stable-${COMMIT}/server/` - Extracted server

You can successfully run VS Code Remote-SSH in completely air-gapped environments without any download attempts or failures.
