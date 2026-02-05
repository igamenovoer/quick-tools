# Open VSX Helper Scripts

This directory contains PowerShell scripts to interact with the [Open VSX Registry](https://open-vsx.org/), an open-source alternative to the Visual Studio Marketplace. These scripts allow you to search for and download extensions without needing the `ovsx` CLI tool.

## Scripts

### 1. Search for Extensions (`search-openvsx.ps1`)

Use this script to find extensions by keyword. It queries the Open VSX API and returns the Extension ID, Version, and Description.

**Usage:**
```powershell
.\search-openvsx.ps1 -Query "<keyword>"
```

**Example:**
```powershell
# Search for Python extensions
.\search-openvsx.ps1 "python"

# Search for a specific theme
.\search-openvsx.ps1 "dracula"
```

### 2. Download Extensions (`download-openvsx.ps1`)

Use this script to download the `.vsix` file for an extension. You can download the latest version or specify a particular one.

**Usage:**
```powershell
.\download-openvsx.ps1 -ExtensionId "<publisher>.<name>" [-Version "<version>"] [-OutputDir "<path>"]
```

**Examples:**
```powershell
# Download the latest version of redhat.java
.\download-openvsx.ps1 "redhat.java"

# Download a specific version
.\download-openvsx.ps1 "redhat.java" -Version "1.0.0"

# Download to a specific folder
.\download-openvsx.ps1 "redhat.java" -OutputDir "C:\Downloads"
```

## Implementation Details

For those interested in how these scripts communicate with the Open VSX API without an official client, here is the logic used:

### Search Logic (`search-openvsx.ps1`)
1.  **API Endpoint:** The script sends a `GET` request to the search endpoint:
    `https://open-vsx.org/api/-/search?query=<KEYWORD>&size=<LIMIT>`
2.  **Request:** It uses PowerShell's `Invoke-RestMethod` to call this URL.
3.  **Parsing:** The API returns a JSON object. The script navigates the `extensions` array in the JSON response to extract the `namespace` (publisher), `name`, `version`, and `description` for display.

### Download Logic (`download-openvsx.ps1`)
1.  **Version Resolution (Optional):**
    - If no version is specified, the script first calls the metadata endpoint:
      `https://open-vsx.org/api/<namespace>/<name>`
    - It parses the JSON response to retrieve the `version` field (which represents the latest stable version).
2.  **URL Construction:** The download URL is constructed using the standard Open VSX pattern:
    `https://open-vsx.org/api/<namespace>.<name>/<version>/file/<namespace>.<name>-<version>.vsix`
    *Note the dot separator between namespace and name in the filename.*
3.  **Download:** It uses `Invoke-WebRequest` to download the file from the constructed URL and saves it to the specified output directory.

## Manual Download URL Format

If you prefer to download manually or need to construct the URL for another tool, the format is:

```
https://open-vsx.org/api/<publisher>.<name>/<version>/file/<publisher>.<name>-<version>.vsix
```

**Example:**
`https://open-vsx.org/api/redhat.java/1.0.0/file/redhat.java-1.0.0.vsix`

## Web Interface

You can also search and download directly from the website: [https://open-vsx.org/](https://open-vsx.org/)