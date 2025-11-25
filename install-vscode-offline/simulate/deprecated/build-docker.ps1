[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Tag = "vscode-airgap-server:latest"
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "Building VS Code airgap server image..." -ForegroundColor Cyan
Write-Host "  Context : $scriptDir" -ForegroundColor DarkCyan
Write-Host "  Tag     : $Tag" -ForegroundColor DarkCyan

Push-Location $scriptDir
try {
    docker build -f server.Dockerfile -t $Tag .
}
finally {
    Pop-Location
}
