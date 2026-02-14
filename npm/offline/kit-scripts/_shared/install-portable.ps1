<#
Usage:
  pwsh .\install-portable.ps1 -Platform win32_x64
  pwsh .\install-portable.ps1 -Platform linux_x64 -VerifyOnly
  pwsh .\install-portable.ps1 -Platform mac_arm64 -Force

Notes:
  - Called by per-platform wrapper scripts under `scripts/<platform-id>/`.
  - Installs into `<kit>/installed/<platform-id>/` without network access.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('win32_x64','linux_x64','linux_arm64','mac_arm64','mac_x64')]
    [string]$Platform,

    [switch]$VerifyOnly,

    [switch]$RunScripts,

    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Info { param([string]$Message) [Console]::Error.WriteLine($Message) }
function Die { param([string]$Message) throw $Message }

function Get-KitRootFromSharedScript {
    $kit = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')
    return $kit.Path
}

function Get-Rel {
    param([string]$KitRoot, [string]$Path)
    $full = (Resolve-Path -LiteralPath $Path).Path
    return $full.Substring($KitRoot.Length + 1).Replace('\','/')
}

function Read-Checksums {
    param([string]$KitRoot)
    $path = Join-Path $KitRoot 'checksums.sha256'
    if (-not (Test-Path -LiteralPath $path)) { Die "Missing checksums file: $path" }
    $map = @{}
    foreach ($line in (Get-Content -LiteralPath $path -Encoding UTF8)) {
        $t = $line.Trim()
        if (-not $t) { continue }
        if ($t -notmatch '^(?<hash>[a-f0-9]{64})\s{2,}(?<rel>.+)$') { continue }
        $map[$Matches.rel] = $Matches.hash
    }
    return $map
}

function Verify-FileHash {
    param(
        [string]$KitRoot,
        [hashtable]$Checksums,
        [string]$RelativePath
    )
    $rel = $RelativePath.Replace('\','/').TrimStart('/')
    if (-not $Checksums.ContainsKey($rel)) { Die "checksums.sha256 missing entry: $rel" }
    $path = Join-Path $KitRoot $rel
    if (-not (Test-Path -LiteralPath $path)) { Die "Missing file: $path" }
    $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    $expected = $Checksums[$rel]
    if ($actual -ne $expected) { Die "Checksum mismatch: $rel" }
}

$kitRoot = Get-KitRootFromSharedScript
$checksums = Read-Checksums -KitRoot $kitRoot

$payloadNodeDir = Join-Path $kitRoot ("payloads\\{0}\\node" -f $Platform)
$payloadPnpmDir = Join-Path $kitRoot ("payloads\\{0}\\pnpm" -f $Platform)
$payloadCommonTools = Join-Path $kitRoot "payloads\\common\\tools"
$payloadStore = Join-Path $kitRoot "payloads\\common\\pnpm-store"
if (-not (Test-Path -LiteralPath $payloadStore)) { Die "Missing pnpm-store: $payloadStore" }

$portable = Get-ChildItem -LiteralPath $payloadNodeDir -File | Where-Object { $_.Name -like 'node-portable*' } | Select-Object -First 1
if (-not $portable) { Die "Missing Node portable artifact in: $payloadNodeDir" }

$pnpmExe = Join-Path $payloadPnpmDir $(if ($Platform -eq 'win32_x64') { 'pnpm.exe' } else { 'pnpm' })
if (-not (Test-Path -LiteralPath $pnpmExe)) { Die "Missing pnpm payload: $pnpmExe" }

Verify-FileHash -KitRoot $kitRoot -Checksums $checksums -RelativePath (Get-Rel -KitRoot $kitRoot -Path $portable.FullName)
Verify-FileHash -KitRoot $kitRoot -Checksums $checksums -RelativePath (Get-Rel -KitRoot $kitRoot -Path $pnpmExe)
Verify-FileHash -KitRoot $kitRoot -Checksums $checksums -RelativePath (Get-Rel -KitRoot $kitRoot -Path (Join-Path $payloadNodeDir 'SHASUMS256.txt'))
Verify-FileHash -KitRoot $kitRoot -Checksums $checksums -RelativePath (Get-Rel -KitRoot $kitRoot -Path (Join-Path $payloadCommonTools 'package.json'))
Verify-FileHash -KitRoot $kitRoot -Checksums $checksums -RelativePath (Get-Rel -KitRoot $kitRoot -Path (Join-Path $payloadCommonTools 'pnpm-lock.yaml'))

if ($VerifyOnly) {
    Write-Info "OK (verify-only)."
    exit 0
}

$prefix = Join-Path $kitRoot ("installed\\{0}" -f $Platform)
$nodeDir = Join-Path $prefix 'node'
$pnpmHome = Join-Path $prefix 'pnpm-bin'
$npmPrefix = Join-Path $prefix 'npm-prefix'
$toolsDir = Join-Path $prefix 'tools'

if ((Test-Path -LiteralPath $prefix) -and $Force) {
    Remove-Item -Recurse -Force -LiteralPath $prefix
}

New-Item -ItemType Directory -Force -Path $nodeDir, $pnpmHome, $npmPrefix, $toolsDir | Out-Null

Write-Info "Installing Node (portable) to: $nodeDir"
if ($Platform -eq 'win32_x64') {
    $temp = Join-Path $env:TEMP ("npm-offline-kit-node-{0}" -f ([guid]::NewGuid().ToString('N')))
    New-Item -ItemType Directory -Force -Path $temp | Out-Null
    try {
        Expand-Archive -LiteralPath $portable.FullName -DestinationPath $temp -Force
        $inner = Get-ChildItem -LiteralPath $temp -Directory | Select-Object -First 1
        if (-not $inner) { Die "Unexpected Node zip structure: $($portable.Name)" }
        Copy-Item -Recurse -Force -Path (Join-Path $inner.FullName '*') -Destination $nodeDir
    } finally {
        Remove-Item -Recurse -Force -LiteralPath $temp -ErrorAction SilentlyContinue
    }
} else {
    $tar = Get-Command tar -ErrorAction SilentlyContinue
    if (-not $tar) { Die "tar not found. Required to extract: $($portable.Name)" }
    & tar -xJf $portable.FullName -C $nodeDir --strip-components=1
}

Write-Info "Installing pnpm to: $pnpmHome"
Copy-Item -Force -LiteralPath $pnpmExe -Destination (Join-Path $pnpmHome (Split-Path -Leaf $pnpmExe))

Write-Info "Installing tools (offline) to: $toolsDir"
Copy-Item -Force -LiteralPath (Join-Path $payloadCommonTools 'package.json') -Destination (Join-Path $toolsDir 'package.json')
Copy-Item -Force -LiteralPath (Join-Path $payloadCommonTools 'pnpm-lock.yaml') -Destination (Join-Path $toolsDir 'pnpm-lock.yaml')

$pnpmLocal = Join-Path $pnpmHome (Split-Path -Leaf $pnpmExe)
$args = @('install','--offline','--frozen-lockfile','--store-dir', $payloadStore)
if (-not $RunScripts) { $args += '--ignore-scripts' }
Push-Location $toolsDir
try {
    & $pnpmLocal @args
} finally {
    Pop-Location
}

Write-Info ""
Write-Info "Portable install complete."
Write-Info "Activate for current session:"
if ($Platform -eq 'win32_x64') {
    Write-Info "  cmd.exe: call `"$kitRoot\\scripts\\$Platform\\activate.bat`" --kit-root `"$kitRoot`""
    Write-Info "  pwsh  : . `"$kitRoot\\scripts\\$Platform\\activate.ps1`" -KitRoot `"$kitRoot`""
} else {
    Write-Info "  . `"$kitRoot/scripts/$Platform/activate.sh`" --kit-root `"$kitRoot`""
}
