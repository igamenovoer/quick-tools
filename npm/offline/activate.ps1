[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$KitRoot,

    [Parameter(Mandatory = $false)]
    [string]$Platform,

    [switch]$Persist,
    [switch]$NoSession,
    [switch]$Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-KitRootFromScriptLocation {
    param([string]$ScriptRoot)

    $current = (Resolve-Path -LiteralPath $ScriptRoot).Path
    while ($true) {
        if (Test-Path -LiteralPath (Join-Path $current 'config.toml')) { return $current }
        if (Test-Path -LiteralPath (Join-Path $current 'config.yaml')) { return $current }
        if (Test-Path -LiteralPath (Join-Path $current 'payloads')) { return $current }
        if (Test-Path -LiteralPath (Join-Path $current 'installed')) { return $current }

        $parent = Split-Path -Parent $current
        if (-not $parent -or $parent -eq $current) { break }
        $current = $parent
    }

    throw "Could not infer -KitRoot. Pass -KitRoot."
}

function Get-WindowsPlatformId {
    $dirPlatform = Split-Path -Leaf $PSScriptRoot
    if ($dirPlatform -eq 'win32_x64') { return 'win32_x64' }

    $arch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString().ToLowerInvariant()
    switch ($arch) {
        'x64' { return 'win32_x64' }
        'arm64' { throw "Windows ARM64 is not supported for v1." }
        default { throw "Unsupported Windows architecture: $arch" }
    }
}

function Add-PathEntry {
    param(
        [string]$PathValue,
        [string]$Entry
    )

    if ([string]::IsNullOrWhiteSpace($Entry)) {
        return $PathValue
    }

    $parts = @()
    if (-not [string]::IsNullOrWhiteSpace($PathValue)) {
        $parts = $PathValue.Split(';') | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    }

    $normalizedParts = $parts | ForEach-Object { $_.Trim() }
    if ($normalizedParts -contains $Entry) {
        return ($parts -join ';')
    }

    return (@($Entry) + $parts) -join ';'
}

if (-not $KitRoot) {
    $KitRoot = Get-KitRootFromScriptLocation -ScriptRoot $PSScriptRoot
} else {
    $KitRoot = (Resolve-Path -LiteralPath $KitRoot).Path
}

if (-not $Platform) {
    $Platform = Get-WindowsPlatformId
}

$prefix = Join-Path $KitRoot ("installed\{0}" -f $Platform)
$nodeBin = Join-Path $prefix 'node'
$npmPrefix = Join-Path $prefix 'npm-prefix'
$pnpmHome = Join-Path $prefix 'pnpm-bin'
$toolsBin = Join-Path $prefix 'tools\node_modules\.bin'
$toolBin = Join-Path $prefix 'bin'

if (-not (Test-Path -LiteralPath (Join-Path $nodeBin 'node.exe'))) {
    if (-not $Persist) {
        throw "Node not found: $(Join-Path $nodeBin 'node.exe')"
    }
}

$sessionPath = $env:Path
$sessionPath = Add-PathEntry -PathValue $sessionPath -Entry $nodeBin
$sessionPath = Add-PathEntry -PathValue $sessionPath -Entry $pnpmHome
$sessionPath = Add-PathEntry -PathValue $sessionPath -Entry (Join-Path $npmPrefix 'bin')
$sessionPath = Add-PathEntry -PathValue $sessionPath -Entry $toolsBin
$sessionPath = Add-PathEntry -PathValue $sessionPath -Entry $toolBin

if (-not $NoSession) {
    $env:NPM_OFFLINE_KIT_ROOT = $KitRoot
    $env:NPM_OFFLINE_PLATFORM = $Platform
    $env:NPM_CONFIG_PREFIX = $npmPrefix
    $env:PNPM_HOME = $pnpmHome
    $env:Path = $sessionPath
}

if ($Persist) {
    [Environment]::SetEnvironmentVariable('NPM_OFFLINE_KIT_ROOT', $KitRoot, 'User')
    [Environment]::SetEnvironmentVariable('NPM_OFFLINE_PLATFORM', $Platform, 'User')
    [Environment]::SetEnvironmentVariable('NPM_CONFIG_PREFIX', $npmPrefix, 'User')
    [Environment]::SetEnvironmentVariable('PNPM_HOME', $pnpmHome, 'User')

    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $userPath = Add-PathEntry -PathValue $userPath -Entry $nodeBin
    $userPath = Add-PathEntry -PathValue $userPath -Entry $pnpmHome
    $userPath = Add-PathEntry -PathValue $userPath -Entry (Join-Path $npmPrefix 'bin')
    $userPath = Add-PathEntry -PathValue $userPath -Entry $toolsBin
    $userPath = Add-PathEntry -PathValue $userPath -Entry $toolBin
    [Environment]::SetEnvironmentVariable('Path', $userPath, 'User')
}

if (-not $Quiet) {
    [Console]::Error.WriteLine(("Activated kit: {0}" -f $KitRoot))
    [Console]::Error.WriteLine(("Platform: {0}" -f $Platform))
    if ($Persist) {
        [Console]::Error.WriteLine("Persisted user env vars. Restart shells to pick up PATH changes.")
    } elseif ($NoSession) {
        [Console]::Error.WriteLine("No session changes requested (-NoSession).")
    }
}
