[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Tag = "vscode-airgap-terminal:latest",

    [Parameter(Mandatory = $false)]
    [string]$SshUsername = "vscode-tester",

    [Parameter(Mandatory = $false)]
    [string]$SshPassword = "123456",

    [Parameter(Mandatory = $false)]
    [switch]$NoCache
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "[info] Building VS Code airgap terminal image..." -ForegroundColor Cyan
Write-Host "       Context    : $scriptDir" -ForegroundColor DarkCyan
Write-Host "       Tag        : $Tag" -ForegroundColor DarkCyan
Write-Host "       SSH user   : $SshUsername" -ForegroundColor DarkCyan
Write-Host "       SSH pass   : $SshPassword" -ForegroundColor DarkCyan
if ($NoCache) {
    Write-Host "       No cache   : enabled" -ForegroundColor DarkCyan
}

Push-Location $scriptDir
try {
    $args = @(
        "build"
        "-f", "terminal.Dockerfile"
        "--tag", $Tag
        "--build-arg", "SSH_USERNAME=$SshUsername"
        "--build-arg", "SSH_PASSWORD=$SshPassword"
    )

    if ($NoCache) {
        $args += "--no-cache"
    }

    $args += "."

    podman @args
}
finally {
    Pop-Location
}
