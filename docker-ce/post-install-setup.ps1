<#
.SYNOPSIS
 Post-installation setup for Docker Engine in WSL2.

.DESCRIPTION
 Configures Docker Engine after installation to make it fully usable:
  - Adds the current user to the docker group (run Docker without sudo)
  - Enables Docker services to start automatically
  - Configures PowerShell access method (Native CLI, Wrapper functions, or both)
  - Optionally exposes Docker daemon via TCP for Windows CLI access
  - Optionally sets DOCKER_HOST environment variable in Windows
  - Verifies the installation

.PARAMETER Distro
 Name of the WSL distribution. Defaults to 'Ubuntu'.

.PARAMETER PowerShellMethod
 How to access Docker from PowerShell:
  - 'NativeCLI' (default): Install Windows Docker CLI + expose via TCP
  - 'Wrapper': Add wrapper functions to PowerShell profile
  - 'Both': Setup both methods
  - 'None': Skip PowerShell configuration

.PARAMETER TcpPort
 Port for Docker TCP exposure. Defaults to 2375.

.PARAMETER SkipUserGroup
 If specified, skips adding user to docker group (useful if already done).

.PARAMETER SkipAutoStart
 If specified, skips enabling Docker services to start automatically.

.PARAMETER SkipCLIInstall
 If specified with PowerShellMethod=NativeCLI or Both, skips installing Docker CLI.

.PARAMETER RunTests
 If specified, runs test commands to verify Docker is working properly.

.EXAMPLE
 ./post-install-setup.ps1

.EXAMPLE
 ./post-install-setup.ps1 -PowerShellMethod Both -RunTests

.EXAMPLE
 ./post-install-setup.ps1 -PowerShellMethod Wrapper -RunTests

.EXAMPLE
 ./post-install-setup.ps1 -Distro Ubuntu -PowerShellMethod NativeCLI -TcpPort 2375 -RunTests

.NOTES
 - Run this after install-docker-engine-wsl.ps1
 - Requires WSL with systemd enabled
 - TCP exposure without TLS is insecure; keep it bound to 127.0.0.1
 - Default PowerShellMethod is 'NativeCLI' (installs native Docker CLI)
#>

[CmdletBinding()]
param(
  [string]$Distro = 'Ubuntu',
  [ValidateSet('NativeCLI', 'Wrapper', 'Both', 'None')]
  [string]$PowerShellMethod = 'NativeCLI',
  [int]$TcpPort = 2375,
  [switch]$SkipUserGroup,
  [switch]$SkipAutoStart,
  [switch]$SkipCLIInstall,
  [switch]$RunTests
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Info($msg)  { Write-Host "[INFO]  $msg" -ForegroundColor Cyan }
function Write-Warn($msg)  { Write-Host "[WARN]  $msg" -ForegroundColor Yellow }
function Write-Err($msg)   { Write-Host "[ERROR] $msg" -ForegroundColor Red }
function Write-Success($msg) { Write-Host "[SUCCESS] $msg" -ForegroundColor Green }

function Invoke-WSL {
  param(
    [Parameter(Mandatory=$true)][string]$DistroName,
    [Parameter(Mandatory=$true)][string]$Command,
    [switch]$AsRoot,
    [switch]$IgnoreErrors
  )
  $args = @('-d', $DistroName)
  if ($AsRoot) { $args += @('-u','root') }
  $args += @('--','bash','-lc', $Command)
  try {
    & wsl.exe @args
  } catch {
    if ($IgnoreErrors) { return } else { throw }
  }
}

function Get-WSLDistros {
  try {
    $out = & wsl.exe -l -q 2>$null | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    return @($out)
  } catch { return @() }
}

function Add-UserToDockerGroup($DistroName) {
  if ($SkipUserGroup) {
    Write-Info "Skipping user group configuration (SkipUserGroup specified)."
    return
  }

  try {
    $linuxUser = (Invoke-WSL -DistroName $DistroName -Command 'id -un').Trim()
    if (-not $linuxUser) { $linuxUser = 'root' }

    Write-Info "Adding user '$linuxUser' to docker group..."

    # Ensure docker group exists
    Invoke-WSL -DistroName $DistroName -Command 'groupadd docker 2>/dev/null || true' -AsRoot -IgnoreErrors

    # Add user to docker group
    Invoke-WSL -DistroName $DistroName -Command "usermod -aG docker $linuxUser" -AsRoot

    Write-Success "User '$linuxUser' added to docker group."
    Write-Warn "Group membership changes take effect on next login. Open a new WSL shell to use docker without sudo."
  } catch {
    Write-Err "Failed to add user to docker group: $($_.Exception.Message)"
    throw
  }
}

function Enable-DockerAutoStart($DistroName) {
  if ($SkipAutoStart) {
    Write-Info "Skipping auto-start configuration (SkipAutoStart specified)."
    return
  }

  Write-Info "Enabling Docker services to start automatically..."

  try {
    Invoke-WSL -DistroName $DistroName -Command 'systemctl enable docker.service' -AsRoot -IgnoreErrors
    Invoke-WSL -DistroName $DistroName -Command 'systemctl enable containerd.service' -AsRoot -IgnoreErrors

    Write-Success "Docker services enabled for automatic startup."
  } catch {
    Write-Warn "Could not enable auto-start: $($_.Exception.Message)"
  }
}

function Configure-TcpExposure($DistroName, [int]$Port) {
  Write-Info "Configuring Docker daemon to listen on tcp://127.0.0.1:$Port..."

  try {
    # Create systemd override directory
    Invoke-WSL -DistroName $DistroName -Command 'mkdir -p /etc/systemd/system/docker.service.d' -AsRoot

    # Create override configuration
    $overrideContent = @"
[Service]
ExecStart=
ExecStart=/usr/bin/dockerd -H unix:///var/run/docker.sock -H tcp://127.0.0.1:$Port --containerd=/run/containerd/containerd.sock
"@

    $overrideContent | & wsl.exe -d $DistroName -u root tee /etc/systemd/system/docker.service.d/override.conf | Out-Null

    # Remove any conflicting daemon.json
    Invoke-WSL -DistroName $DistroName -Command 'rm -f /etc/docker/daemon.json' -AsRoot -IgnoreErrors

    # Reload systemd and restart Docker
    Write-Info "Reloading systemd and restarting Docker..."
    Invoke-WSL -DistroName $DistroName -Command 'systemctl daemon-reload' -AsRoot
    Invoke-WSL -DistroName $DistroName -Command 'systemctl restart docker' -AsRoot

    Start-Sleep -Seconds 3

    # Verify Docker is listening on TCP
    $listening = Invoke-WSL -DistroName $DistroName -Command "netstat -tlnp 2>/dev/null | grep $Port || ss -tlnp 2>/dev/null | grep $Port" -AsRoot -IgnoreErrors

    if ($listening) {
      Write-Success "Docker daemon is now listening on tcp://127.0.0.1:$Port"
      Write-Warn "TCP exposure without TLS is insecure. Keep it bound to 127.0.0.1 only."
    } else {
      Write-Warn "Could not verify TCP listener. Check Docker service status."
    }
  } catch {
    Write-Err "Failed to configure TCP exposure: $($_.Exception.Message)"
    throw
  }
}

function Test-IsAdmin {
  $currentIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = New-Object System.Security.Principal.WindowsPrincipal($currentIdentity)
  return $principal.IsInRole([System.Security.Principal.WindowsBuiltinRole]::Administrator)
}

function Request-AdminElevation {
  Write-Warn "Administrator privileges required to set system environment variables."
  Write-Host ""
  $response = Read-Host "Restart this script with administrator privileges? (Y/n)"

  if ($response -match '^[Nn]') {
    Write-Info "Continuing without admin privileges. DOCKER_HOST will be set for current user only."
    return $false
  }

  try {
    Write-Info "Restarting script with administrator privileges..."
    $scriptPath = $PSCommandPath

    # Build argument list
    $argList = @()
    foreach ($param in $PSBoundParameters.GetEnumerator()) {
      if ($param.Value -is [switch] -or $param.Value -is [bool]) {
        if ($param.Value) {
          $argList += "-$($param.Key)"
        }
      } else {
        $argList += "-$($param.Key)"
        $argList += "`"$($param.Value)`""
      }
    }

    $arguments = $argList -join ' '

    Start-Process powershell.exe -Verb RunAs -ArgumentList "-ExecutionPolicy Bypass -File `"$scriptPath`" $arguments"
    exit 0
  } catch {
    Write-Err "Failed to elevate: $($_.Exception.Message)"
    Write-Info "Continuing without admin privileges. DOCKER_HOST will be set for current user only."
    return $false
  }
}

function Set-WindowsDockerHostEnv([int]$Port) {
  $value = "tcp://127.0.0.1:$Port"

  $isAdmin = Test-IsAdmin
  $scope = if ($isAdmin) { 'Machine' } else { 'User' }

  if (-not $isAdmin) {
    Write-Warn "Not running as Administrator."
    $elevated = Request-AdminElevation
    if ($elevated) {
      return  # Script will restart with admin privileges
    }
  }

  Write-Info "Setting $scope environment variable DOCKER_HOST=$value"

  try {
    [System.Environment]::SetEnvironmentVariable('DOCKER_HOST', $value, $scope)
    Write-Success "DOCKER_HOST environment variable set at $scope level."

    # Also set for current session
    $env:DOCKER_HOST = $value
    Write-Info "DOCKER_HOST also set for current PowerShell session."

    if ($scope -eq 'Machine') {
      Write-Success "System-level variable set! Available to all users and processes immediately."
    } else {
      Write-Warn "User-level variable set. Restart PowerShell for the change to take effect in new sessions."
    }
  } catch {
    Write-Err "Failed to set DOCKER_HOST: $($_.Exception.Message)"
    Write-Info "You can set it manually: [System.Environment]::SetEnvironmentVariable('DOCKER_HOST', '$value', 'User')"
  }
}

function Install-DockerCLI {
  Write-Info "Installing Windows Docker CLI..."

  # Check if winget is available
  if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Err "winget not found. Please install Docker CLI manually:"
    Write-Host "  Download from: https://download.docker.com/win/static/stable/x86_64/" -ForegroundColor Gray
    return $false
  }

  # Check if Docker CLI already installed
  if (Get-Command docker.exe -ErrorAction SilentlyContinue) {
    $version = & docker.exe --version 2>$null
    Write-Success "Docker CLI already installed: $version"
    return $true
  }

  try {
    Write-Info "Installing via winget (this may take a minute)..."
    $output = & winget install Docker.DockerCLI --silent --accept-package-agreements --accept-source-agreements 2>&1

    if ($LASTEXITCODE -eq 0 -or $output -match "successfully installed") {
      Write-Success "Docker CLI installed successfully!"
      Write-Warn "You need to restart PowerShell for docker.exe to be in PATH."
      return $true
    } else {
      Write-Warn "winget installation may have failed. Check output above."
      return $false
    }
  } catch {
    Write-Err "Failed to install Docker CLI: $($_.Exception.Message)"
    Write-Host "  You can install manually with: winget install Docker.DockerCLI" -ForegroundColor Gray
    return $false
  }
}

function Add-PowerShellWrapperFunctions([string]$DistroName) {
  Write-Info "Adding Docker wrapper functions to PowerShell profile..."

  # Ensure profile directory exists
  $profileDir = Split-Path -Parent $PROFILE
  if (-not (Test-Path $profileDir)) {
    Write-Info "Creating PowerShell profile directory: $profileDir"
    New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
  }

  # Check if profile exists
  $profileExists = Test-Path $PROFILE
  if (-not $profileExists) {
    Write-Info "Creating PowerShell profile: $PROFILE"
    New-Item -ItemType File -Path $PROFILE -Force | Out-Null
  }

  # Read existing profile
  $profileContent = if ($profileExists) { Get-Content $PROFILE -Raw } else { "" }

  # Check if functions already exist
  $hasDockerFunctions = $profileContent -match "# Docker CLI wrapper functions"

  if ($hasDockerFunctions) {
    Write-Info "Docker functions already exist in profile. Updating..."
    # Remove old functions
    $profileContent = $profileContent -replace "(?s)# Docker CLI wrapper functions.*?(?=\r?\n\r?\n|\z)", ""
  }

  # Prepare functions to add
  $wrapperFunctions = @"

# Docker CLI wrapper functions (added by post-install-setup.ps1)
function docker { wsl -d $DistroName docker @args }
function docker-compose { wsl -d $DistroName docker compose @args }

# Load DOCKER_HOST for current session if set
if ([System.Environment]::GetEnvironmentVariable('DOCKER_HOST', 'Machine')) {
  `$env:DOCKER_HOST = [System.Environment]::GetEnvironmentVariable('DOCKER_HOST', 'Machine')
} elseif ([System.Environment]::GetEnvironmentVariable('DOCKER_HOST', 'User')) {
  `$env:DOCKER_HOST = [System.Environment]::GetEnvironmentVariable('DOCKER_HOST', 'User')
}

"@

  # Add new functions
  $newContent = $profileContent.TrimEnd() + $wrapperFunctions

  try {
    Set-Content -Path $PROFILE -Value $newContent -NoNewline
    Write-Success "Docker wrapper functions added to PowerShell profile!"
    Write-Info "Profile location: $PROFILE"
    Write-Info "Profile will also load DOCKER_HOST automatically."
    Write-Warn "Run '. `$PROFILE' to use the functions immediately (or restart PowerShell)."
    return $true
  } catch {
    Write-Err "Failed to update PowerShell profile: $($_.Exception.Message)"
    return $false
  }
}

function Test-DockerInstallation($DistroName) {
  Write-Info "Running Docker tests..."

  try {
    # Test 1: Docker version
    Write-Info "Test 1: Checking Docker version..."
    $version = (Invoke-WSL -DistroName $DistroName -Command 'docker --version').Trim()
    Write-Success "  $version"

    # Test 2: Docker daemon connection
    Write-Info "Test 2: Checking Docker daemon connection..."
    $info = Invoke-WSL -DistroName $DistroName -Command 'docker info --format "Server Version: {{.ServerVersion}}, Storage Driver: {{.Driver}}"'
    Write-Success "  $info"

    # Test 3: Docker Compose version
    Write-Info "Test 3: Checking Docker Compose..."
    $composeVersion = (Invoke-WSL -DistroName $DistroName -Command 'docker compose version').Trim()
    Write-Success "  $composeVersion"

    # Test 4: Run hello-world
    Write-Info "Test 4: Running hello-world container..."
    $helloOutput = Invoke-WSL -DistroName $DistroName -Command 'docker run --rm hello-world 2>&1'

    if ($helloOutput -match "Hello from Docker") {
      Write-Success "  hello-world container ran successfully!"
    } else {
      Write-Warn "  hello-world test produced unexpected output."
    }

    Write-Success "All tests completed!"

  } catch {
    Write-Err "Docker tests failed: $($_.Exception.Message)"
    throw
  }
}

# --- Main ---

Write-Host ""
Write-Host "=====================================" -ForegroundColor Magenta
Write-Host "Docker Engine Post-Install Setup" -ForegroundColor Magenta
Write-Host "=====================================" -ForegroundColor Magenta
Write-Host ""

# Verify WSL is available
if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
  throw 'wsl.exe not found. Install WSL first.'
}

# Verify distro exists
$distros = Get-WSLDistros
if ($distros -notcontains $Distro) {
  throw "WSL distro '$Distro' not found. Install it first or specify a different distro."
}

Write-Info "Configuring Docker in WSL distro: $Distro"
Write-Info "PowerShell access method: $PowerShellMethod"
Write-Host ""

# Step 1: Add user to docker group
Add-UserToDockerGroup -DistroName $Distro

# Step 2: Enable auto-start
Enable-DockerAutoStart -DistroName $Distro

# Step 3: Configure PowerShell access method
$needsTcp = $PowerShellMethod -eq 'NativeCLI' -or $PowerShellMethod -eq 'Both'
$needsWrapper = $PowerShellMethod -eq 'Wrapper' -or $PowerShellMethod -eq 'Both'

if ($PowerShellMethod -ne 'None') {
  Write-Host ""
  Write-Host "=====================================" -ForegroundColor Magenta
  Write-Host "Configuring PowerShell Access" -ForegroundColor Magenta
  Write-Host "=====================================" -ForegroundColor Magenta
  Write-Host ""
}

# Configure TCP exposure for Native CLI
if ($needsTcp) {
  Configure-TcpExposure -DistroName $Distro -Port $TcpPort
  Set-WindowsDockerHostEnv -Port $TcpPort

  if (-not $SkipCLIInstall) {
    Write-Host ""
    Install-DockerCLI | Out-Null
  } else {
    Write-Info "Skipping Docker CLI installation (SkipCLIInstall specified)."
    Write-Info "Install later with: winget install Docker.DockerCLI"
  }
}

# Configure wrapper functions
if ($needsWrapper) {
  Write-Host ""
  Add-PowerShellWrapperFunctions -DistroName $Distro | Out-Null
}

# Step 4: Run tests (optional)
if ($RunTests) {
  Write-Host ""
  Test-DockerInstallation -DistroName $Distro
}

# Summary
Write-Host ""
Write-Host "=====================================" -ForegroundColor Magenta
Write-Host "Post-Install Setup Complete!" -ForegroundColor Green
Write-Host "=====================================" -ForegroundColor Magenta
Write-Host ""

Write-Host "Summary:" -ForegroundColor Cyan
Write-Host "  - User added to docker group: $(-not $SkipUserGroup)" -ForegroundColor Gray
Write-Host "  - Auto-start enabled: $(-not $SkipAutoStart)" -ForegroundColor Gray
Write-Host "  - PowerShell access method: $PowerShellMethod" -ForegroundColor Gray

if ($needsTcp) {
  Write-Host "  - TCP exposure (port $TcpPort): Enabled" -ForegroundColor Gray
  $dockerHostScope = if (Test-IsAdmin) { "System (Machine)" } else { "User" }
  Write-Host "  - DOCKER_HOST set: $dockerHostScope level" -ForegroundColor Gray
  if (-not $SkipCLIInstall) {
    Write-Host "  - Native Docker CLI: Installed/Available" -ForegroundColor Gray
  } else {
    Write-Host "  - Native Docker CLI: Skipped" -ForegroundColor Gray
  }
}

if ($needsWrapper) {
  Write-Host "  - PowerShell wrapper functions: Added to profile" -ForegroundColor Gray
}

Write-Host ""

# Next steps based on configuration
Write-Host "Next steps:" -ForegroundColor Yellow

if (-not $SkipUserGroup) {
  Write-Host "  1. Open a new WSL shell (wsl -d $Distro) to apply group changes" -ForegroundColor Gray
}

if ($needsWrapper) {
  Write-Host "  2. Restart PowerShell or run: . `$PROFILE" -ForegroundColor Gray
  Write-Host "  3. Test with: docker ps" -ForegroundColor Gray
  Write-Host "     (Uses wrapper function: wsl docker ps)" -ForegroundColor DarkGray
}

if ($needsTcp) {
  if ($needsWrapper) {
    Write-Host "  4. For native Docker CLI: Reload profile or restart PowerShell" -ForegroundColor Gray
  } else {
    if (Test-IsAdmin) {
      Write-Host "  2. DOCKER_HOST is available immediately (system-level)" -ForegroundColor Gray
      Write-Host "  3. Current session ready! Test with: docker ps" -ForegroundColor Gray
    } else {
      Write-Host "  2. DOCKER_HOST is set for your user" -ForegroundColor Gray
      Write-Host "  3. Reload profile: . `$PROFILE" -ForegroundColor Gray
      Write-Host "     (Or restart PowerShell)" -ForegroundColor Gray
    }
  }
  Write-Host "  5. Test with: docker ps" -ForegroundColor Gray
  Write-Host "     (Uses native docker.exe via TCP)" -ForegroundColor DarkGray
}

Write-Host ""

# Quick test command
Write-Host "Quick test (works immediately):" -ForegroundColor Yellow
Write-Host "  wsl -d $Distro docker ps" -ForegroundColor DarkGray
Write-Host ""

# Wait for user input before closing
Write-Host "Press any key to close..." -ForegroundColor DarkGray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
