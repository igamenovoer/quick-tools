[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('win32_x64','linux_x64','linux_arm64','mac_arm64','mac_x64')]
    [string]$Platform
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Die { param([string]$Message) throw $Message }

function Get-KitRootFromSharedScript {
    $kit = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')
    return $kit.Path
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

function Verify-Rel {
    param([string]$KitRoot, [hashtable]$Checksums, [string]$RelPath)
    $rel = $RelPath.Replace('\','/').TrimStart('/')
    if (-not $Checksums.ContainsKey($rel)) { Die "checksums.sha256 missing entry: $rel" }
    $path = Join-Path $KitRoot $rel
    if (-not (Test-Path -LiteralPath $path)) { Die "Missing file: $path" }
    $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $Checksums[$rel]) { Die "Checksum mismatch: $rel" }
}

$kitRoot = Get-KitRootFromSharedScript
$checksums = Read-Checksums -KitRoot $kitRoot

Verify-Rel -KitRoot $kitRoot -Checksums $checksums -RelPath "payloads/$Platform/node/SHASUMS256.txt"
Verify-Rel -KitRoot $kitRoot -Checksums $checksums -RelPath "payloads/$Platform/pnpm/$(if ($Platform -eq 'win32_x64') { 'pnpm.exe' } else { 'pnpm' })"
Verify-Rel -KitRoot $kitRoot -Checksums $checksums -RelPath "payloads/common/tools/package.json"
Verify-Rel -KitRoot $kitRoot -Checksums $checksums -RelPath "payloads/common/tools/pnpm-lock.yaml"

if (-not (Test-Path -LiteralPath (Join-Path $kitRoot "payloads\\common\\pnpm-store"))) {
    Die "Missing pnpm-store: payloads/common/pnpm-store"
}

$nodePortable = Get-ChildItem -LiteralPath (Join-Path $kitRoot "payloads\\$Platform\\node") -File | Where-Object { $_.Name -like 'node-portable*' } | Select-Object -First 1
if (-not $nodePortable) { Die "Missing node-portable artifact under payloads/$Platform/node" }
Verify-Rel -KitRoot $kitRoot -Checksums $checksums -RelPath ("payloads/$Platform/node/$($nodePortable.Name)")

if (Test-Path -LiteralPath (Join-Path $kitRoot "payloads\\$Platform\\node\\node-installer.msi")) {
    Verify-Rel -KitRoot $kitRoot -Checksums $checksums -RelPath "payloads/$Platform/node/node-installer.msi"
}
if (Test-Path -LiteralPath (Join-Path $kitRoot "payloads\\$Platform\\node\\node-installer.pkg")) {
    Verify-Rel -KitRoot $kitRoot -Checksums $checksums -RelPath "payloads/$Platform/node/node-installer.pkg"
}

[Console]::Error.WriteLine("OK")
