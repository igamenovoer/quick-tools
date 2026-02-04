<#
.SYNOPSIS
    Installs Pixi on Windows (online or from a pre-downloaded archive).
.DESCRIPTION
    Default behavior uses Pixi’s official installer script:
        Invoke-RestMethod https://pixi.sh/install.ps1 | Invoke-Expression

    Offline mode: provide -PackagePath pointing to a downloaded Pixi release archive
    (not extracted). In that mode, this script mimics the official installer logic:
    - extracts the archive into "$PixiHome\\bin"
    - prepends that bin dir to the *user* PATH (HKCU:\\Environment), unless -NoPathUpdate
.PARAMETER PackagePath
    Path to a downloaded Pixi archive (zip) to install from (not extracted).
.PARAMETER PixiVersion
    Pixi version to install when using the online official installer. Default: 'latest'.
.PARAMETER PixiHome
    Pixi home directory. Default: "$Env:USERPROFILE\\.pixi".
.PARAMETER NoPathUpdate
    If specified, do not update the PATH environment variable.
.PARAMETER PixiRepoUrl
    Pixi repo url for the online official installer.
.PARAMETER InstallScriptUrl
    URL for the official PowerShell installer script.
.NOTES
    - This script updates the *user* PATH, matching the official installer behavior.
    - For offline installs, download the Pixi release archive for Windows (zip) first.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string] $PackagePath,

    [Parameter()]
    [string] $PixiVersion = 'latest',

    [Parameter()]
    [string] $PixiHome = "$Env:USERPROFILE\.pixi",

    [Parameter()]
    [switch] $NoPathUpdate,

    [Parameter()]
    [string] $PixiRepoUrl = 'https://github.com/prefix-dev/pixi',

    [Parameter()]
    [string] $InstallScriptUrl = 'https://pixi.sh/install.ps1'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Publish-Env {
    if (-not ("Win32.NativeMethods" -as [Type])) {
        Add-Type -Namespace Win32 -Name NativeMethods -MemberDefinition @"
[DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
public static extern IntPtr SendMessageTimeout(
    IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam,
    uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
"@
    }

    $HWND_BROADCAST = [IntPtr] 0xffff
    $WM_SETTINGCHANGE = 0x1a
    $result = [UIntPtr]::Zero

    [Win32.Nativemethods]::SendMessageTimeout(
        $HWND_BROADCAST,
        $WM_SETTINGCHANGE,
        [UIntPtr]::Zero,
        "Environment",
        2,
        5000,
        [ref] $result
    ) | Out-Null
}

function Write-UserEnv {
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [AllowNull()]
        [string] $Value
    )

    $registryKey = Get-Item -Path 'HKCU:'
    $envRegistryKey = $registryKey.OpenSubKey('Environment', $true)
    if ($null -eq $Value) {
        $envRegistryKey.DeleteValue($Name)
    } else {
        $registryValueKind = if ($Value.Contains('%')) {
            [Microsoft.Win32.RegistryValueKind]::ExpandString
        } elseif ($envRegistryKey.GetValue($Name)) {
            $envRegistryKey.GetValueKind($Name)
        } else {
            [Microsoft.Win32.RegistryValueKind]::String
        }
        $envRegistryKey.SetValue($Name, $Value, $registryValueKind)
    }

    Publish-Env
}

function Get-UserEnv {
    param(
        [Parameter(Mandatory)]
        [string] $Name
    )

    $registryKey = Get-Item -Path 'HKCU:'
    $envRegistryKey = $registryKey.OpenSubKey('Environment')
    $registryValueOption = [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames
    return $envRegistryKey.GetValue($Name, $null, $registryValueOption)
}

function Add-To-UserPath {
    param(
        [Parameter(Mandatory)]
        [string] $PathToAdd
    )

    $currentPath = Get-UserEnv -Name 'PATH'
    if ([string]::IsNullOrWhiteSpace($currentPath)) {
        $currentPath = ""
    }

    if ($currentPath -notlike "*$PathToAdd*") {
        Write-Output "Adding $PathToAdd to PATH"
        $newPath = if ([string]::IsNullOrEmpty($currentPath)) { $PathToAdd } else { "$PathToAdd;$currentPath" }
        Write-UserEnv -Name 'PATH' -Value $newPath
        $Env:PATH = $newPath
        Write-Output "You may need to restart your shell"
    } else {
        Write-Output "$PathToAdd is already in PATH"
    }
}

function Install-PixiFromArchive {
    param(
        [Parameter(Mandatory)]
        [string] $ArchivePath,

        [Parameter(Mandatory)]
        [string] $PixiHomePath,

        [Parameter(Mandatory)]
        [bool] $SkipPathUpdate
    )

    $resolvedArchivePath = (Resolve-Path -Path $ArchivePath).Path
    if (-not (Test-Path -Path $resolvedArchivePath -PathType Leaf)) {
        throw "PackagePath does not exist or is not a file: $resolvedArchivePath"
    }

    if ([System.IO.Path]::GetExtension($resolvedArchivePath) -ne '.zip') {
        throw "Offline install currently supports .zip archives only. Got: $resolvedArchivePath"
    }

    $binDir = Join-Path -Path $PixiHomePath -ChildPath 'bin'
    if (-not (Test-Path -Path $binDir)) {
        New-Item -ItemType Directory -Path $binDir | Out-Null
    }

    Write-Output "Installing Pixi from archive: $resolvedArchivePath"
    Write-Output "Extracting into: $binDir"

    Expand-Archive -Path $resolvedArchivePath -DestinationPath $binDir -Force

    $pixiExePath = Join-Path -Path $binDir -ChildPath 'pixi.exe'
    if (-not (Test-Path -Path $pixiExePath -PathType Leaf)) {
        $candidate = Get-ChildItem -Path $binDir -Recurse -File -Filter 'pixi*.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -ne $candidate) {
            Move-Item -Path $candidate.FullName -Destination $pixiExePath -Force
        }
    }

    if (-not (Test-Path -Path $pixiExePath -PathType Leaf)) {
        throw "Could not locate pixi.exe after extraction. Check the archive contents: $resolvedArchivePath"
    }

    Write-Output "Installed: $pixiExePath"

    if (-not $SkipPathUpdate) {
        Add-To-UserPath -PathToAdd $binDir
    } else {
        Write-Output "Skipping PATH update (-NoPathUpdate)"
    }
}

# Match the official installer’s env var overrides when parameters aren’t explicitly provided.
if ($Env:PIXI_VERSION -and -not $PSBoundParameters.ContainsKey('PixiVersion')) {
    $PixiVersion = $Env:PIXI_VERSION
}

if ($Env:PIXI_HOME -and -not $PSBoundParameters.ContainsKey('PixiHome')) {
    $PixiHome = $Env:PIXI_HOME
}

if ($Env:PIXI_NO_PATH_UPDATE -and -not $PSBoundParameters.ContainsKey('NoPathUpdate')) {
    $NoPathUpdate = $true
}

if ($Env:PIXI_REPOURL -and -not $PSBoundParameters.ContainsKey('PixiRepoUrl')) {
    $PixiRepoUrl = $Env:PIXI_REPOURL -replace '/$', ''
}

if ([string]::IsNullOrWhiteSpace($PackagePath)) {
    # Online install via official script (default).
    $Env:PIXI_VERSION = $PixiVersion
    $Env:PIXI_HOME = $PixiHome
    $Env:PIXI_REPOURL = $PixiRepoUrl
    if ($NoPathUpdate) {
        $Env:PIXI_NO_PATH_UPDATE = '1'
    } else {
        Remove-Item -Path Env:PIXI_NO_PATH_UPDATE -ErrorAction SilentlyContinue
    }

    Invoke-RestMethod $InstallScriptUrl | Invoke-Expression
    exit 0
}

Install-PixiFromArchive -ArchivePath $PackagePath -PixiHomePath $PixiHome -SkipPathUpdate ([bool]$NoPathUpdate)
