# How to Download VS Code Extensions for Offline Use

This guide shows how to download VS Code extensions as `.vsix` files for air‑gapped environments. It recommends using **Open VSX** via the `ovsx` CLI when possible, with the Marketplace used only as a fallback.

## 1. Install `ovsx` (Open VSX CLI)

`ovsx` is an open‑source CLI for the [Open VSX Registry](https://open-vsx.org/). It can publish and download VS Code extensions as `.vsix` files.

Install with npm:

```bash
npm install -g ovsx
```

Validate the installation:

```bash
ovsx -h
ovsx get --help
```

You should see usage output describing commands like `get`, `publish`, and `login`.

## 2. Download Extensions from Open VSX

Most popular extensions are mirrored on Open VSX. To download a `.vsix`:

```bash
cd /path/to/install-vscode-offline/simulate/pkgs/extensions

# Example: Remote‑SSH (if available on Open VSX)
ovsx get ms-vscode-remote.remote-ssh -o ms-vscode-remote.remote-ssh-openvsx.vsix

# Example: Markdown Preview Enhanced
ovsx get shd101wyy.markdown-preview-enhanced -o shd101wyy.markdown-preview-enhanced-openvsx.vsix

# Example: Claude Dev / Cline
ovsx get saoudrizwan.claude-dev -o saoudrizwan.claude-dev-openvsx.vsix
```

To verify that the file is a valid VSIX (ZIP):

```bash
unzip -t <extension>.vsix
```

or, in Python:

```bash
python -c "import zipfile; zipfile.ZipFile('<extension>.vsix').testzip()"
```

If there is no error, the VSIX is valid.

## 3. Fallback: Marketplace `vspackage` Downloads

If an extension is **not** published on Open VSX, you can still download from the VS Code Marketplace using the `vspackage` API:

```text
https://marketplace.visualstudio.com/_apis/public/gallery/publishers/<publisher>/vsextensions/<extension>/latest/vspackage
```

Example:

```powershell
$url = "https://marketplace.visualstudio.com/_apis/public/gallery/publishers/ms-vscode-remote/vsextensions/remote-ssh/latest/vspackage"
$out = "ms-vscode-remote.remote-ssh-latest.vsix"

$wc = New-Object System.Net.WebClient
$wc.DownloadFile($url, $out)
```

Always validate the downloaded file as a ZIP. If `unzip` or `zipfile` reports “not a zip file”, the response was likely HTML or a redirect, not a real VSIX.

## 4. Integration with This Repository

Scripts in this repo already prefer `ovsx` when it is available:

- `download-latest-vscode-package.ps1` uses `ovsx get` for Remote‑SSH extensions and falls back to the Marketplace only on failure.
- `tmp/redownload-vsix.ps1` uses `ovsx` to fetch known third‑party extensions into `simulate/pkgs/extensions`.

For best results:

1. Install `ovsx` on an online machine.
2. Use the commands above to download `.vsix` files into `install-vscode-offline/simulate/pkgs/extensions/`.
3. Verify each `.vsix` as a valid ZIP archive.
4. Transfer the `pkgs/extensions` directory into your air‑gapped environment before building Docker images.

