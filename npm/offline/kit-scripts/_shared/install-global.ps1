<#
Usage:
  pwsh .\install-global.ps1 -Platform win32_x64
  pwsh .\install-global.ps1 -Platform win32_x64 -VerifyOnly
  pwsh .\install-global.ps1 -Platform win32_x64 -Force

Notes:
  - Windows-only global installer entry.
  - Requires Administrator privileges.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('win32_x64','linux_x64','linux_arm64','mac_arm64','mac_x64')]
    [string]$Platform,

    [switch]$VerifyOnly,

    [switch]$RunScripts,

    [switch]$Force,

    [switch]$Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Info { param([string]$Message) if (-not $Quiet) { [Console]::Error.WriteLine($Message) } }
function Die { param([string]$Message) throw $Message }

function Get-KitRootFromSharedScript {
    $kit = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')
    return $kit.Path
}

function Test-IsAdmin {
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
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

if ($Platform -ne 'win32_x64') {
    Die "This Windows global installer only supports win32_x64. Use the .sh global installers on Linux/macOS."
}

if (-not (Test-IsAdmin)) {
    Die "Global install requires Administrator privileges. Re-run from an elevated PowerShell / cmd.exe."
}

$payloadNodeDir = Join-Path $kitRoot "payloads\\$Platform\\node"
$payloadPnpmDir = Join-Path $kitRoot "payloads\\$Platform\\pnpm"
$payloadCommonTools = Join-Path $kitRoot "payloads\\common\\tools"
$payloadStore = Join-Path $kitRoot "payloads\\common\\pnpm-store"
if (-not (Test-Path -LiteralPath $payloadStore)) { Die "Missing pnpm-store: $payloadStore" }

$msi = Join-Path $payloadNodeDir 'node-installer.msi'
if (-not (Test-Path -LiteralPath $msi)) { Die "Missing Node MSI: $msi" }
$pnpmExe = Join-Path $payloadPnpmDir 'pnpm.exe'
if (-not (Test-Path -LiteralPath $pnpmExe)) { Die "Missing pnpm: $pnpmExe" }

Verify-FileHash -KitRoot $kitRoot -Checksums $checksums -RelativePath ("payloads/$Platform/node/node-installer.msi")
Verify-FileHash -KitRoot $kitRoot -Checksums $checksums -RelativePath ("payloads/$Platform/pnpm/pnpm.exe")
Verify-FileHash -KitRoot $kitRoot -Checksums $checksums -RelativePath ("payloads/common/tools/package.json")
Verify-FileHash -KitRoot $kitRoot -Checksums $checksums -RelativePath ("payloads/common/tools/pnpm-lock.yaml")

if ($VerifyOnly) {
    Write-Info "OK (verify-only)."
    exit 0
}

Write-Info "Installing Node.js globally via MSI..."
Start-Process -FilePath "msiexec.exe" -ArgumentList @('/i', $msi) -Wait

$systemRoot = Join-Path ${env:ProgramFiles} 'npm-offline-kit'
$systemPnpmDir = Join-Path $systemRoot 'pnpm'
$systemToolsDir = Join-Path $systemRoot 'tools'

if ((Test-Path -LiteralPath $systemRoot) -and $Force) {
    Remove-Item -Recurse -Force -LiteralPath $systemRoot
}

New-Item -ItemType Directory -Force -Path $systemPnpmDir, $systemToolsDir | Out-Null
Copy-Item -Force -LiteralPath $pnpmExe -Destination (Join-Path $systemPnpmDir 'pnpm.exe')

Copy-Item -Force -LiteralPath (Join-Path $payloadCommonTools 'package.json') -Destination (Join-Path $systemToolsDir 'package.json')
Copy-Item -Force -LiteralPath (Join-Path $payloadCommonTools 'pnpm-lock.yaml') -Destination (Join-Path $systemToolsDir 'pnpm-lock.yaml')

$args = @('install','--offline','--frozen-lockfile','--store-dir', $payloadStore)
if (-not $RunScripts) { $args += '--ignore-scripts' }
Push-Location $systemToolsDir
try {
    & (Join-Path $systemPnpmDir 'pnpm.exe') @args
} finally {
    Pop-Location
}

Write-Info "Updating machine PATH..."
function Add-ToMachinePath {
    param([string]$Entry)
    $current = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $parts = @()
    if ($current) { $parts = $current.Split(';') | ForEach-Object { $_.Trim() } | Where-Object { $_ } }
    if ($parts -contains $Entry) { return }
    $new = (@($Entry) + $parts) -join ';'
    [Environment]::SetEnvironmentVariable('Path', $new, 'Machine')
}

Add-ToMachinePath -Entry $systemPnpmDir
Add-ToMachinePath -Entry (Join-Path $systemToolsDir 'node_modules\.bin')

Write-Info "Global install complete. Open a new shell to pick up PATH changes."
