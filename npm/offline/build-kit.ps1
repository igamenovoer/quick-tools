<#
Usage:
  pwsh .\build-kit.ps1 -ConfigPath .\config.toml -OutputDir .\dist\npm-offline-kit -Force
  pwsh .\build-kit.ps1 -ConfigPath .\config.toml -NoPnpmStore

What this does:
  - Resolves Node/pnpm versions (latest by default, optional pinning from config).
  - Downloads Node + pnpm artifacts and verifies Node checksums.
  - Resolves package versions, writes lockfile, and prefetches pnpm store.
  - Emits a portable offline kit directory with per-platform scripts.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ConfigPath = (Join-Path (Get-Location) 'config.toml'),

    [Parameter(Mandatory = $false)]
    [string]$OutputDir,

    [switch]$Force,

    [switch]$NoPnpmStore
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$Script:SupportedPlatforms = @('win32_x64', 'linux_x64', 'linux_arm64', 'mac_arm64', 'mac_x64')

function Write-Info { param([string]$Message) [Console]::Error.WriteLine($Message) }
function Die { param([string]$Message) throw $Message }

function Ensure-Dir {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path | Out-Null
    }
}

function Get-Sha256Hex {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Download-File {
    param(
        [string]$Url,
        [string]$OutFile
    )
    Ensure-Dir -Path (Split-Path -Parent $OutFile)
    if (Test-Path -LiteralPath $OutFile) {
        return
    }

    Write-Info "Downloading: $Url"
    Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing
}

function Read-TextFile {
    param([string]$Path)
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8
}

function Parse-TomlValue {
    param([string]$ValueText)

    $v = $ValueText.Trim()

    if ($v -match '^(true|false)$') {
        return ($v -eq 'true')
    }

    if ($v -match '^[0-9]+$') {
        return [int]$v
    }

    if ($v.StartsWith('"') -and $v.EndsWith('"')) {
        $inner = $v.Substring(1, $v.Length - 2)
        $inner = $inner.Replace('\"', '"')
        return $inner
    }

    if ($v.StartsWith('[')) {
        if (-not $v.Contains(']')) { Die "Unterminated TOML array: $ValueText" }
        $inside = $v.Substring(1, $v.IndexOf(']') - 1)
        $items = @()
        foreach ($raw in ($inside -split ',')) {
            $item = $raw.Trim()
            if (-not $item) { continue }
            $items += (Parse-TomlValue -ValueText $item)
        }
        return ,$items
    }

    Die "Unsupported TOML value: $ValueText"
}

function Parse-TomlSimple {
    param([string]$TomlText)

    $result = @{}
    $currentTable = $result

    $lines = $TomlText -split "(`r`n|`n|`r)"
    $i = 0
    while ($i -lt $lines.Length) {
        $line = $lines[$i]
        $i++

        $line = $line.Trim()
        if (-not $line) { continue }
        if ($line.StartsWith('#')) { continue }

        if ($line -match '^\[(?<table>[^\]]+)\]$') {
            $tableName = $Matches.table.Trim()
            if (-not $tableName) { Die "Invalid TOML table header: $line" }
            if (-not $result.ContainsKey($tableName)) {
                $result[$tableName] = @{}
            }
            if (-not ($result[$tableName] -is [hashtable])) {
                Die "TOML table name collides with non-table value: [$tableName]"
            }
            $currentTable = $result[$tableName]
            continue
        }

        if ($line -notmatch '^(?<key>[A-Za-z0-9_-]+)\s*=\s*(?<value>.*)$') {
            Die "Unsupported TOML line: $line"
        }

        $key = $Matches.key
        $valuePart = $Matches.value.Trim()

        if ($valuePart.StartsWith('[') -and -not ($valuePart -match '\]$')) {
            while ($i -lt $lines.Length) {
                $valuePart += "`n" + $lines[$i]
                $i++
                if ($valuePart -match '\]') { break }
            }
        }

        $currentTable[$key] = Parse-TomlValue -ValueText $valuePart
    }

    return $result
}

function Normalize-NodeVersionTag {
    param([string]$NodeVersion)
    if ($NodeVersion.StartsWith('v')) { return $NodeVersion }
    return "v$NodeVersion"
}

function Get-LatestNodeVersionTag {
    $index = Invoke-RestMethod -Uri 'https://nodejs.org/dist/index.json' -UseBasicParsing
    $stable = $index | Where-Object { $_.version -match '^v\d+\.\d+\.\d+$' } | Select-Object -First 1
    if (-not $stable) { Die "Could not determine latest Node version from index.json." }
    return $stable.version
}

function Get-LatestPnpmVersion {
    $latest = Invoke-RestMethod -Uri 'https://registry.npmjs.org/pnpm/latest' -UseBasicParsing
    if (-not $latest.version) { Die "Could not determine pnpm latest version from registry." }
    return [string]$latest.version
}

function Get-PnpmReleaseAssets {
    param([string]$PnpmVersion)
    $tag = "v$PnpmVersion"
    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/pnpm/pnpm/releases/tags/$tag" -Headers @{ 'User-Agent' = 'npm-offline-kit' }
    if (-not $release.assets) { Die "No pnpm release assets found for $tag." }
    return $release.assets
}

function Get-PnpmAssetNameForPlatform {
    param([string]$PlatformId)
    switch ($PlatformId) {
        'win32_x64' { return 'pnpm-win-x64.exe' }
        'linux_x64' { return 'pnpm-linuxstatic-x64' }
        'linux_arm64' { return 'pnpm-linuxstatic-arm64' }
        'mac_x64' { return 'pnpm-macos-x64' }
        'mac_arm64' { return 'pnpm-macos-arm64' }
        default { Die "Unsupported platform id for pnpm: $PlatformId" }
    }
}

function Get-HostPlatformId {
    $arch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString().ToLowerInvariant()

    if ([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows)) {
        if ($arch -ne 'x64') { Die "Host Windows arch not supported for build: $arch" }
        return 'win32_x64'
    }

    if ([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Linux)) {
        switch ($arch) {
            'x64' { return 'linux_x64' }
            'arm64' { return 'linux_arm64' }
            default { Die "Host Linux arch not supported for build: $arch" }
        }
    }

    if ([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::OSX)) {
        switch ($arch) {
            'x64' { return 'mac_x64' }
            'arm64' { return 'mac_arm64' }
            default { Die "Host macOS arch not supported for build: $arch" }
        }
    }

    Die "Unsupported host OS for build."
}

function Get-NodePortableNameForPlatform {
    param(
        [string]$PlatformId,
        [string]$NodeVersionTag
    )
    $ver = $NodeVersionTag.TrimStart('v')
    switch ($PlatformId) {
        'win32_x64' { return "node-v$ver-win-x64.zip" }
        'linux_x64' { return "node-v$ver-linux-x64.tar.xz" }
        'linux_arm64' { return "node-v$ver-linux-arm64.tar.xz" }
        'mac_x64' { return "node-v$ver-darwin-x64.tar.xz" }
        'mac_arm64' { return "node-v$ver-darwin-arm64.tar.xz" }
        default { Die "Unsupported platform id for Node portable: $PlatformId" }
    }
}

function Get-NodeInstallerNameForPlatform {
    param(
        [string]$PlatformId,
        [string]$NodeVersionTag
    )
    $ver = $NodeVersionTag.TrimStart('v')
    switch ($PlatformId) {
        'win32_x64' { return "node-v$ver-x64.msi" }
        'mac_x64' { return "node-v$ver.pkg" }
        'mac_arm64' { return "node-v$ver.pkg" }
        default { return $null }
    }
}

function Parse-PackageSpec {
    param([string]$Spec)
    $s = $Spec.Trim()
    if (-not $s) { Die "Empty package spec." }

    if ($s.StartsWith('@')) {
        $at = $s.LastIndexOf('@')
        if ($at -le 0) { return @{ Name = $s; Version = 'latest'; Spec = $s } }
        $slash = $s.IndexOf('/')
        if ($slash -lt 0) { return @{ Name = $s; Version = 'latest'; Spec = $s } }
        if ($at -le $slash) { return @{ Name = $s; Version = 'latest'; Spec = $s } }
        return @{ Name = $s.Substring(0, $at); Version = $s.Substring($at + 1); Spec = $s }
    }

    $at2 = $s.LastIndexOf('@')
    if ($at2 -gt 0) {
        return @{ Name = $s.Substring(0, $at2); Version = $s.Substring($at2 + 1); Spec = $s }
    }

    return @{ Name = $s; Version = 'latest'; Spec = $s }
}

function Validate-Config {
    param([hashtable]$Config)

    if ($Config.ContainsKey('schema_version')) {
        if (-not ($Config.schema_version -is [int])) { Die "config.toml: schema_version must be an integer" }
        if ($Config.schema_version -ne 1) { Die "config.toml: unsupported schema_version: $($Config.schema_version) (supported: 1)" }
    }

    if (-not $Config.ContainsKey('platforms')) { Die "config.toml: missing [platforms]" }
    if (-not ($Config.platforms -is [hashtable])) { Die "config.toml: [platforms] must be a table" }
    if (-not $Config.ContainsKey('packages')) { Die "config.toml: missing packages = [ ... ]" }
    if (-not ($Config.packages -is [object[]])) { Die "config.toml: packages must be an array" }
    if ($Config.packages.Count -lt 1) { Die "config.toml: packages must include at least 1 entry" }

    foreach ($k in $Config.platforms.Keys) {
        if (-not ($Script:SupportedPlatforms -contains $k)) {
            Die "config.toml: unknown platform key in [platforms]: $k"
        }
        if (-not ($Config.platforms[$k] -is [bool])) {
            Die "config.toml: [platforms].$k must be boolean"
        }
    }

    $enabled = @()
    foreach ($platformId in $Script:SupportedPlatforms) {
        if ($Config.platforms.ContainsKey($platformId) -and $Config.platforms[$platformId]) {
            $enabled += $platformId
        }
    }
    if ($enabled.Count -lt 1) { Die "config.toml: enable at least one platform under [platforms]" }

    $seen = @{}
    foreach ($p in $Config.packages) {
        if (-not ($p -is [string])) { Die "config.toml: packages entries must be strings" }
        $p2 = $p.Trim()
        if (-not $p2) { Die "config.toml: packages entries must be non-empty" }
        if ($seen.ContainsKey($p2)) { Die "config.toml: duplicate packages entry: $p2" }
        $seen[$p2] = $true
    }

    if ($Config.ContainsKey('versions')) {
        if (-not ($Config.versions -is [hashtable])) { Die "config.toml: [versions] must be a table" }
        foreach ($k in $Config.versions.Keys) {
            if ($k -notin @('node', 'pnpm')) { Die "config.toml: unknown key in [versions]: $k" }
        }
        if ($Config.versions.ContainsKey('node')) {
            $n = [string]$Config.versions.node
            if ($n -notmatch '^v?\d+\.\d+\.\d+$') { Die "config.toml: versions.node must be like 25.6.1 or v25.6.1" }
        }
        if ($Config.versions.ContainsKey('pnpm')) {
            $p = [string]$Config.versions.pnpm
            if ($p -notmatch '^\d+\.\d+\.\d+$') { Die "config.toml: versions.pnpm must be like 10.29.3" }
        }
    }

    return $enabled
}

function Write-ChecksumsFile {
    param(
        [string]$KitRoot,
        [hashtable]$FileHashes
    )
    $outPath = Join-Path $KitRoot 'checksums.sha256'
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($rel in ($FileHashes.Keys | Sort-Object)) {
        $lines.Add(("{0}  {1}" -f $FileHashes[$rel], $rel.Replace('\', '/')))
    }
    [IO.File]::WriteAllLines($outPath, $lines, (New-Object Text.UTF8Encoding($false)))
}

function Copy-KitScripts {
    param(
        [string]$RepoRoot,
        [string]$KitRoot,
        [string[]]$Platforms
    )

    $kitScripts = Join-Path $KitRoot 'scripts'
    Ensure-Dir -Path $kitScripts

    $sharedSrc = Join-Path $RepoRoot 'quick-tools\npm\offline\kit-scripts\_shared'
    $sharedDst = Join-Path $kitScripts '_shared'
    Copy-Item -Recurse -Force -Path $sharedSrc -Destination $sharedDst

    foreach ($platformId in $Platforms) {
        $dst = Join-Path $kitScripts $platformId
        Ensure-Dir -Path $dst

        if ($platformId -eq 'win32_x64') {
            Copy-Item -Force (Join-Path $RepoRoot 'quick-tools\npm\offline\activate.bat') (Join-Path $dst 'activate.bat')
            Copy-Item -Force (Join-Path $RepoRoot 'quick-tools\npm\offline\activate.ps1') (Join-Path $dst 'activate.ps1')

            $portableBat = @'
@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\_shared\install-portable.ps1" -Platform __PLATFORM__ %*
exit /b %errorlevel%
'@.Replace('__PLATFORM__', $platformId)

            $globalBat = @'
@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\_shared\install-global.ps1" -Platform __PLATFORM__ %*
exit /b %errorlevel%
'@.Replace('__PLATFORM__', $platformId)

            $verifyBat = @'
@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\_shared\verify.ps1" -Platform __PLATFORM__ %*
exit /b %errorlevel%
'@.Replace('__PLATFORM__', $platformId)

            Set-Content -LiteralPath (Join-Path $dst 'install-portable.bat') -Encoding ASCII -Value $portableBat
            Set-Content -LiteralPath (Join-Path $dst 'install-global.bat') -Encoding ASCII -Value $globalBat
            Set-Content -LiteralPath (Join-Path $dst 'verify.bat') -Encoding ASCII -Value $verifyBat

            Set-Content -LiteralPath (Join-Path $dst 'install-portable.ps1') -Encoding UTF8 -Value "& (Join-Path `$PSScriptRoot '..\\_shared\\install-portable.ps1') -Platform '$platformId' @args`r`n"
            Set-Content -LiteralPath (Join-Path $dst 'install-global.ps1') -Encoding UTF8 -Value "& (Join-Path `$PSScriptRoot '..\\_shared\\install-global.ps1') -Platform '$platformId' @args`r`n"
            Set-Content -LiteralPath (Join-Path $dst 'verify.ps1') -Encoding UTF8 -Value "& (Join-Path `$PSScriptRoot '..\\_shared\\verify.ps1') -Platform '$platformId' @args`r`n"
        } else {
            Copy-Item -Force (Join-Path $RepoRoot 'quick-tools\npm\offline\activate.sh') (Join-Path $dst 'activate.sh')

            $portableWrapper = @'
#!/usr/bin/env sh
set -eu
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec "$script_dir/../_shared/install-portable.sh" --platform __PLATFORM__ "$@"
'@.Replace('__PLATFORM__', $platformId)

            $globalWrapper = @'
#!/usr/bin/env sh
set -eu
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec "$script_dir/../_shared/install-global.sh" --platform __PLATFORM__ "$@"
'@.Replace('__PLATFORM__', $platformId)

            $verifyWrapper = @'
#!/usr/bin/env sh
set -eu
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec "$script_dir/../_shared/verify.sh" --platform __PLATFORM__ "$@"
'@.Replace('__PLATFORM__', $platformId)

            Set-Content -LiteralPath (Join-Path $dst 'install-portable.sh') -Encoding UTF8 -Value $portableWrapper
            Set-Content -LiteralPath (Join-Path $dst 'install-global.sh') -Encoding UTF8 -Value $globalWrapper
            Set-Content -LiteralPath (Join-Path $dst 'verify.sh') -Encoding UTF8 -Value $verifyWrapper
        }
    }
}

if (-not (Test-Path -LiteralPath $ConfigPath)) {
    Die "Config not found: $ConfigPath"
}

$configText = Read-TextFile -Path $ConfigPath
$config = Parse-TomlSimple -TomlText $configText
$enabledPlatforms = Validate-Config -Config $config

$nodeVersionTag = $null
if ($config.ContainsKey('versions') -and $config.versions.ContainsKey('node')) {
    $nodeVersionTag = Normalize-NodeVersionTag -NodeVersion ([string]$config.versions.node)
} else {
    $nodeVersionTag = Get-LatestNodeVersionTag
}

$pnpmVersion = $null
if ($config.ContainsKey('versions') -and $config.versions.ContainsKey('pnpm')) {
    $pnpmVersion = [string]$config.versions.pnpm
} else {
    $pnpmVersion = Get-LatestPnpmVersion
}

if (-not $OutputDir) {
    if ($config.ContainsKey('output_dir')) {
        $OutputDir = [string]$config.output_dir
    } else {
        $stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss')
        $OutputDir = (Join-Path (Get-Location) ("dist\\npm-offline-kit-$stamp"))
    }
}

if (Test-Path -LiteralPath $OutputDir) {
    if (-not $Force) {
        Die "OutputDir already exists: $OutputDir (use -Force to overwrite)"
    }
    Remove-Item -Recurse -Force -LiteralPath $OutputDir
}

Ensure-Dir -Path $OutputDir

Write-Info "Building kit in: $OutputDir"
Write-Info "Enabled platforms: $($enabledPlatforms -join ', ')"
Write-Info "Node version: $nodeVersionTag"
Write-Info "pnpm version: $pnpmVersion"

Copy-Item -Force -LiteralPath $ConfigPath -Destination (Join-Path $OutputDir 'config.toml')

$payloadsRoot = Join-Path $OutputDir 'payloads'
$commonRoot = Join-Path $payloadsRoot 'common'
Ensure-Dir -Path $commonRoot
Ensure-Dir -Path (Join-Path $commonRoot 'tools')

$fileHashes = @{}

$pnpmAssets = Get-PnpmReleaseAssets -PnpmVersion $pnpmVersion
foreach ($platformId in $enabledPlatforms) {
    $assetName = Get-PnpmAssetNameForPlatform -PlatformId $platformId
    $asset = $pnpmAssets | Where-Object { $_.name -eq $assetName } | Select-Object -First 1
    if (-not $asset) { Die "pnpm release asset not found: $assetName (pnpm $pnpmVersion)" }
    $dstDir = Join-Path $payloadsRoot "$platformId\\pnpm"
    Ensure-Dir -Path $dstDir
    $dstFile = Join-Path $dstDir $(if ($platformId -eq 'win32_x64') { 'pnpm.exe' } else { 'pnpm' })
    Download-File -Url $asset.browser_download_url -OutFile $dstFile

    $rel = (Resolve-Path -LiteralPath $dstFile).Path.Substring((Resolve-Path -LiteralPath $OutputDir).Path.Length + 1)
    $fileHashes[$rel] = Get-Sha256Hex -Path $dstFile
}

# Download a host-native pnpm for build-time resolution/fetch (independent of enabled target platforms).
$hostPlatform = Get-HostPlatformId
$hostAssetName = Get-PnpmAssetNameForPlatform -PlatformId $hostPlatform
$hostAsset = $pnpmAssets | Where-Object { $_.name -eq $hostAssetName } | Select-Object -First 1
if (-not $hostAsset) { Die "pnpm host asset not found: $hostAssetName (pnpm $pnpmVersion)" }

$hostPnpmTempDir = Join-Path $env:TEMP ("npm-offline-kit-pnpm-{0}" -f ([guid]::NewGuid().ToString('N')))
Ensure-Dir -Path $hostPnpmTempDir
$hostPnpmExe = Join-Path $hostPnpmTempDir $(if ($hostPlatform -eq 'win32_x64') { 'pnpm.exe' } else { 'pnpm' })
Download-File -Url $hostAsset.browser_download_url -OutFile $hostPnpmExe

$nodeBase = "https://nodejs.org/dist/$nodeVersionTag"
$shasumsUrl = "$nodeBase/SHASUMS256.txt"

foreach ($platformId in $enabledPlatforms) {
    $nodeDir = Join-Path $payloadsRoot "$platformId\\node"
    Ensure-Dir -Path $nodeDir

    $shasumsPath = Join-Path $nodeDir 'SHASUMS256.txt'
    Download-File -Url $shasumsUrl -OutFile $shasumsPath

    $portableName = Get-NodePortableNameForPlatform -PlatformId $platformId -NodeVersionTag $nodeVersionTag
    $portableUrl = "$nodeBase/$portableName"
    $portableExt = [IO.Path]::GetExtension($portableName)
    if ($portableName.EndsWith('.tar.xz')) { $portableExt = '.tar.xz' }
    $portableDst = Join-Path $nodeDir ("node-portable$portableExt")
    Download-File -Url $portableUrl -OutFile $portableDst

    $installerName = Get-NodeInstallerNameForPlatform -PlatformId $platformId -NodeVersionTag $nodeVersionTag
    if ($installerName) {
        $installerUrl = "$nodeBase/$installerName"
        $installerExt = [IO.Path]::GetExtension($installerName)
        $installerDst = Join-Path $nodeDir ("node-installer$installerExt")
        Download-File -Url $installerUrl -OutFile $installerDst
    }

    $shasumsText = Read-TextFile -Path $shasumsPath
    $expected = @{}
    foreach ($l in ($shasumsText -split "`n")) {
        $t = $l.Trim()
        if (-not $t) { continue }
        if ($t -notmatch '^(?<hash>[a-fA-F0-9]{64})\s+\*?(?<name>.+)$') { continue }
        $expected[$Matches.name.Trim()] = $Matches.hash.ToLowerInvariant()
    }

    $portableHash = Get-Sha256Hex -Path $portableDst
    if (-not $expected.ContainsKey($portableName)) { Die "SHASUMS256.txt missing entry for $portableName" }
    if ($expected[$portableName] -ne $portableHash) { Die "Checksum mismatch for $portableName" }

    $relPortable = (Resolve-Path -LiteralPath $portableDst).Path.Substring((Resolve-Path -LiteralPath $OutputDir).Path.Length + 1)
    $fileHashes[$relPortable] = $portableHash

    $relShasums = (Resolve-Path -LiteralPath $shasumsPath).Path.Substring((Resolve-Path -LiteralPath $OutputDir).Path.Length + 1)
    $fileHashes[$relShasums] = Get-Sha256Hex -Path $shasumsPath

    if ($installerName) {
        $installerPath = Join-Path $nodeDir ("node-installer$installerExt")
        $installerHash = Get-Sha256Hex -Path $installerPath
        if (-not $expected.ContainsKey($installerName)) { Die "SHASUMS256.txt missing entry for $installerName" }
        if ($expected[$installerName] -ne $installerHash) { Die "Checksum mismatch for $installerName" }
        $relInstaller = (Resolve-Path -LiteralPath $installerPath).Path.Substring((Resolve-Path -LiteralPath $OutputDir).Path.Length + 1)
        $fileHashes[$relInstaller] = $installerHash
    }
}

$toolsTemp = Join-Path $env:TEMP ("npm-offline-kit-tools-{0}" -f ([guid]::NewGuid().ToString('N')))
Ensure-Dir -Path $toolsTemp

try {
    $deps = @{}
    foreach ($spec in $config.packages) {
        $p = Parse-PackageSpec -Spec ([string]$spec)
        $deps[$p.Name] = $p.Version
    }

    $pkgJson = @{
        name = 'npm-offline-kit-tools'
        private = $true
        version = '0.0.0'
        description = 'Generated by npm-offline-kit build-kit.ps1'
        dependencies = $deps
    }

    $pkgJsonPath = Join-Path $toolsTemp 'package.json'
    $pkgJson | ConvertTo-Json -Depth 20 | Out-File -LiteralPath $pkgJsonPath -Encoding UTF8

    Write-Info "Resolving tool versions (pnpm lockfile-only)..."
    Push-Location $toolsTemp
    try {
        & $hostPnpmExe install --lockfile-only --ignore-scripts | Out-Null
    } finally {
        Pop-Location
    }

    $lockPath = Join-Path $toolsTemp 'pnpm-lock.yaml'
    if (-not (Test-Path -LiteralPath $lockPath)) { Die "pnpm-lock.yaml not generated." }

    Copy-Item -Force -LiteralPath $pkgJsonPath -Destination (Join-Path $commonRoot 'tools\\package.json')
    Copy-Item -Force -LiteralPath $lockPath -Destination (Join-Path $commonRoot 'tools\\pnpm-lock.yaml')

    $pkgOut = Join-Path $commonRoot 'tools\\package.json'
    $lockOut = Join-Path $commonRoot 'tools\\pnpm-lock.yaml'

    $relPkg = (Resolve-Path -LiteralPath $pkgOut).Path.Substring((Resolve-Path -LiteralPath $OutputDir).Path.Length + 1)
    $fileHashes[$relPkg] = Get-Sha256Hex -Path $pkgOut
    $relLock = (Resolve-Path -LiteralPath $lockOut).Path.Substring((Resolve-Path -LiteralPath $OutputDir).Path.Length + 1)
    $fileHashes[$relLock] = Get-Sha256Hex -Path $lockOut

    if (-not $NoPnpmStore) {
        $storeDir = Join-Path $commonRoot 'pnpm-store'
        Ensure-Dir -Path $storeDir

        Write-Info "Prefetching pnpm store (may take a while)..."
        Push-Location $toolsTemp
        try {
            & $hostPnpmExe fetch --frozen-lockfile --ignore-scripts --store-dir $storeDir | Out-Null
        } finally {
            Pop-Location
        }
    }
} finally {
    Remove-Item -Recurse -Force -LiteralPath $toolsTemp -ErrorAction SilentlyContinue
    Remove-Item -Recurse -Force -LiteralPath $hostPnpmTempDir -ErrorAction SilentlyContinue
}

$repoRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\\..\\..')
Copy-KitScripts -RepoRoot $repoRoot.Path -KitRoot $OutputDir -Platforms $enabledPlatforms

# Include script + config hashes too.
$hashTargets = @(
    (Join-Path $OutputDir 'config.toml')
)
foreach ($f in $hashTargets) {
    if (Test-Path -LiteralPath $f) {
        $rel = (Resolve-Path -LiteralPath $f).Path.Substring((Resolve-Path -LiteralPath $OutputDir).Path.Length + 1)
        $fileHashes[$rel] = Get-Sha256Hex -Path $f
    }
}

Get-ChildItem -LiteralPath (Join-Path $OutputDir 'scripts') -Recurse -File | ForEach-Object {
    $rel = $_.FullName.Substring((Resolve-Path -LiteralPath $OutputDir).Path.Length + 1)
    $fileHashes[$rel] = Get-Sha256Hex -Path $_.FullName
}

Write-ChecksumsFile -KitRoot $OutputDir -FileHashes $fileHashes

$manifestFiles = @{}
foreach ($k in $fileHashes.Keys) {
    $manifestFiles[$k.Replace('\','/')] = $fileHashes[$k]
}

$manifest = @{
    kit_version = 1
    created_utc = (Get-Date).ToUniversalTime().ToString('o')
    node_version = $nodeVersionTag
    pnpm_version = $pnpmVersion
    platforms = $enabledPlatforms
    packages = @($config.packages)
    files = $manifestFiles
}

($manifest | ConvertTo-Json -Depth 30) | Out-File -LiteralPath (Join-Path $OutputDir 'manifest.json') -Encoding UTF8

Write-Info "Done."
