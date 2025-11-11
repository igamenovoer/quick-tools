<#
 .SYNOPSIS
  Install Docker Engine (CE) inside a WSL2 Ubuntu distro, without Docker Desktop.

 .DESCRIPTION
  Automates the steps from howto-install-docker-without-desktop.md:
   - Ensure the target WSL distro exists (default: Ubuntu)
   - Enable systemd in WSL
   - Install Docker Engine + CLI + containerd + Buildx + Compose v2
   - Add the default user to the docker group
   - Enable and start docker services
   - Optionally expose the daemon on 127.0.0.1:2375 and set DOCKER_HOST in Windows

 .PARAMETER Distro
  Name of the WSL distribution to configure. Defaults to 'Ubuntu'.

 .PARAMETER InstallDistro
  If specified and the distro is missing, attempt 'wsl --install -d <Distro>'. Requires admin.

 .PARAMETER ExposeTcp
  If specified, configures /etc/docker/daemon.json to bind both the unix socket and tcp://127.0.0.1:<TcpPort> (no TLS). Insecure; keep loopback-only.

 .PARAMETER TcpPort
  Port for ExposeTcp. Defaults to 2375.

 .PARAMETER SetWindowsDockerHost
  If specified with -ExposeTcp, sets DOCKER_HOST for the current Windows user to tcp://127.0.0.1:<TcpPort>.

 .PARAMETER RunHelloWorld
  If specified, runs 'hello-world' to verify installation (via sudo inside WSL). Pulls an image.

 .EXAMPLE
  ./install-docker-engine-wsl.ps1

 .EXAMPLE
  ./install-docker-engine-wsl.ps1 -Distro Ubuntu -ExposeTcp -SetWindowsDockerHost -RunHelloWorld

 .NOTES
  - Requires Windows 11 with WSL supporting systemd (recent WSL build).
  - If you enable systemd, the script will issue 'wsl --shutdown' to apply.
  - Exposing Docker over TCP without TLS is insecure; keep it bound to 127.0.0.1.
#>

[CmdletBinding()]
param(
  [string]$Distro = 'Ubuntu',
  [switch]$InstallDistro,
  [switch]$ExposeTcp,
  [int]$TcpPort = 2375,
  [switch]$SetWindowsDockerHost,
  [switch]$RunHelloWorld
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Info($msg)  { Write-Host "[INFO]  $msg" -ForegroundColor Cyan }
function Write-Warn($msg)  { Write-Host "[WARN]  $msg" -ForegroundColor Yellow }
function Write-Err($msg)   { Write-Host "[ERROR] $msg" -ForegroundColor Red }

function Test-IsAdmin {
  $currentIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = New-Object System.Security.Principal.WindowsPrincipal($currentIdentity)
  return $principal.IsInRole([System.Security.Principal.WindowsBuiltinRole]::Administrator)
}

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

function Test-WSLSystemd($DistroName) {
  try {
    $comm = Invoke-WSL -DistroName $DistroName -Command "ps -p 1 -o comm= 2>/dev/null" -AsRoot
    return ($comm.Trim() -eq 'systemd')
  } catch { return $false }
}

function Ensure-WSLDistro($DistroName) {
  $distros = Get-WSLDistros
  if ($distros -contains $DistroName) {
    Write-Info "WSL distro '$DistroName' found."
    return
  }
  if (-not $InstallDistro) {
    throw "WSL distro '$DistroName' not found. Install it or rerun with -InstallDistro."
  }
  if (-not (Test-IsAdmin)) {
    throw "Installing a WSL distro requires Administrator. Rerun PowerShell as Admin or install manually."
  }
  Write-Info "Installing WSL distro '$DistroName' via 'wsl --install -d $DistroName'..."
  & wsl.exe --install -d $DistroName
  Write-Warn "If this is a fresh install, launch '$DistroName' from Start to complete first-run setup, then re-run this script."
}

function Ensure-Systemd($DistroName) {
  if (Test-WSLSystemd $DistroName) {
    Write-Info "systemd already active in '$DistroName'."
    return $false
  }
  Write-Info "Enabling systemd in /etc/wsl.conf for '$DistroName'..."
  $enableCmd = @"
set -e
if [ -f /etc/wsl.conf ]; then cp /etc/wsl.conf /etc/wsl.conf.bak 2>/dev/null || true; fi
cat > /etc/wsl.conf <<'EOF'
[boot]
systemd=true
EOF
"@
  Invoke-WSL -DistroName $DistroName -Command $enableCmd -AsRoot
  Write-Info "Shutting down WSL to apply systemd setting..."
  & wsl.exe --shutdown
  Start-Sleep -Seconds 1
  $active = Test-WSLSystemd $DistroName
  if (-not $active) {
    Write-Warn "systemd not detected as PID 1 yet. It will become active when the distro next launches in a normal session."
  } else {
    Write-Info "systemd is active."
  }
  return $true
}

function Install-DockerEngine($DistroName) {
  Write-Info "Installing Docker Engine and components in '$DistroName'..."
  $steps = @(
    'set -e',
    'command -v apt-get >/dev/null 2>&1 || { echo "This script expects an Ubuntu-based distro with apt-get." >&2; exit 1; }',
    'apt-get update',
    'apt-get install -y ca-certificates curl lsb-release',
    'install -m 0755 -d /etc/apt/keyrings',
    'curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc',
    'chmod a+r /etc/apt/keyrings/docker.asc'
  )
  foreach ($cmd in $steps) { Invoke-WSL -DistroName $DistroName -Command $cmd -AsRoot }

  # Create docker.list with proper codename - use a robust multi-step approach
  Write-Info "Configuring Docker repository..."

  # Step 1: Get the codename and architecture separately
  $getCodenameCmd = 'if command -v lsb_release >/dev/null 2>&1; then lsb_release -cs; else . /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}"; fi'
  $codename = (Invoke-WSL -DistroName $DistroName -Command $getCodenameCmd -AsRoot).Trim()

  if ([string]::IsNullOrWhiteSpace($codename)) {
    throw "ERROR: Could not determine Ubuntu codename"
  }

  $arch = (Invoke-WSL -DistroName $DistroName -Command 'dpkg --print-architecture' -AsRoot).Trim()

  if ([string]::IsNullOrWhiteSpace($arch)) {
    throw "ERROR: Could not determine system architecture"
  }

  Write-Info "Detected Ubuntu $codename ($arch)"

  # Step 2: Write docker.list using a here-document (avoids command substitution issues)
  $writeDockerListCmd = @"
cat > /etc/apt/sources.list.d/docker.list <<'DOCKERLIST'
deb [arch=$arch signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $codename stable
DOCKERLIST
"@
  Invoke-WSL -DistroName $DistroName -Command $writeDockerListCmd -AsRoot

  # Step 3: Verify the file was written correctly
  $verifyCmd = 'cat /etc/apt/sources.list.d/docker.list'
  $dockerListContent = (Invoke-WSL -DistroName $DistroName -Command $verifyCmd -AsRoot).Trim()

  $expectedContent = "deb [arch=$arch signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $codename stable"
  if ($dockerListContent -ne $expectedContent) {
    throw "ERROR: docker.list was not written correctly.`nExpected: $expectedContent`nActual: $dockerListContent"
  }

  Write-Info "Docker repository configured successfully"

  # Continue with installation
  $installSteps = @(
    'apt-get update',
    'apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin'
  )
  foreach ($cmd in $installSteps) { Invoke-WSL -DistroName $DistroName -Command $cmd -AsRoot }

  # Ensure services are enabled and started
  Invoke-WSL -DistroName $DistroName -Command 'systemctl enable docker.service' -AsRoot -IgnoreErrors
  Invoke-WSL -DistroName $DistroName -Command 'systemctl enable containerd.service' -AsRoot -IgnoreErrors
  Invoke-WSL -DistroName $DistroName -Command 'systemctl restart docker || systemctl start docker' -AsRoot -IgnoreErrors
}

function Add-UserToDockerGroup($DistroName) {
  try {
    $linuxUser = (Invoke-WSL -DistroName $DistroName -Command 'id -un' ).Trim()
    if (-not $linuxUser) { $linuxUser = 'root' }
    Write-Info "Adding user '$linuxUser' to docker group in '$DistroName'..."
    Invoke-WSL -DistroName $DistroName -Command 'groupadd docker 2>/dev/null || true' -AsRoot -IgnoreErrors
    Invoke-WSL -DistroName $DistroName -Command "usermod -aG docker $linuxUser" -AsRoot
    Write-Warn "Group membership changes take effect on next login. Open a new WSL shell for '$DistroName'."
  } catch {
    Write-Warn "Could not add user to docker group: $($_.Exception.Message)"
  }
}

function Configure-DaemonTcp($DistroName, [int]$Port) {
  $daemonCmd = @'
set -e
mkdir -p /etc/docker
if [ -f /etc/docker/daemon.json ]; then cp /etc/docker/daemon.json /etc/docker/daemon.json.bak.$(date +%s) 2>/dev/null || true; fi
cat > /etc/docker/daemon.json <<EOF
{"hosts":["unix:///var/run/docker.sock","tcp://127.0.0.1:__PORT__"]}
EOF
systemctl restart docker || systemctl start docker
'@
  $daemonCmd = $daemonCmd.Replace('__PORT__', $Port.ToString())
  Write-Info "Configuring daemon to also listen on tcp://127.0.0.1:$Port (no TLS)..."
  Invoke-WSL -DistroName $DistroName -Command $daemonCmd -AsRoot
  Write-Warn "Exposing Docker over TCP without TLS is insecure. Keep it bound to 127.0.0.1 or configure TLS separately."
}

function Set-WindowsDockerHostEnv([int]$Port) {
  $value = "tcp://127.0.0.1:$Port"
  Write-Info "Setting user environment variable DOCKER_HOST=$value"
  [System.Environment]::SetEnvironmentVariable('DOCKER_HOST', $value, 'User')
  Write-Warn 'Restart PowerShell/CMD for the environment change to take effect.'
}

function Verify-Install($DistroName, [switch]$RunHello) {
  try {
    $ver = (Invoke-WSL -DistroName $DistroName -Command 'docker --version' ).Trim()
    Write-Info "Docker in '$DistroName': $ver"
  } catch {
    Write-Warn "Unable to query 'docker --version' in '$DistroName'."
  }
  if ($RunHello) {
    Write-Info "Running 'hello-world' test (this may pull an image)..."
    try {
      Invoke-WSL -DistroName $DistroName -Command 'sudo docker run --rm hello-world'
    } catch {
      Write-Warn "hello-world test failed: $($_.Exception.Message)"
    }
  }
}

# --- Main ---

if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
  throw 'wsl.exe not found. Install WSL first (see Microsoft Learn).'
}

Ensure-WSLDistro -DistroName $Distro

# Enabling systemd (may trigger a WSL shutdown)
$didChangeSystemd = Ensure-Systemd -DistroName $Distro

# Install Docker Engine
Install-DockerEngine -DistroName $Distro

# Add user to docker group
Add-UserToDockerGroup -DistroName $Distro

# Optional: Expose TCP and set Windows DOCKER_HOST
if ($ExposeTcp) {
  Configure-DaemonTcp -DistroName $Distro -Port $TcpPort
  if ($SetWindowsDockerHost) { Set-WindowsDockerHostEnv -Port $TcpPort }
}

# Verify
Verify-Install -DistroName $Distro -RunHello:$RunHelloWorld

Write-Host ''
Write-Host 'Done.' -ForegroundColor Green
Write-Host 'Notes:' -ForegroundColor DarkGray
Write-Host ' - Open a new Ubuntu (WSL) shell for group membership changes to take effect.' -ForegroundColor DarkGray
if ($ExposeTcp) { Write-Host " - Windows CLI: set DOCKER_HOST=tcp://127.0.0.1:$TcpPort (or use -SetWindowsDockerHost)." -ForegroundColor DarkGray }

