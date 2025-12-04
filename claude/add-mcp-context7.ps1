#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Ensure the Context7 MCP server is configured for Claude Code.

.DESCRIPTION
    add-mcp-context7.ps1
    If the server already exists under the chosen scope, it is removed first, then re-added.
    
    Default behavior: scope = user, mcp-name = context7-mcp
    Runner preference: bunx > npx (picks first available)
    Note: context7-mcp is only available as npm package, uvx is not supported.
    Command used to add (example with npx):
      claude mcp add-json -s user context7-mcp '{"command":"npx","args":["-y","@upstash/context7-mcp"]}'

.PARAMETER Scope
    Override scope (default: user). Valid values: local, user, project

.PARAMETER McpName
    Override MCP server name (default: context7-mcp)

.PARAMETER DryRun
    Show actions without executing

.PARAMETER Quiet
    Less output

.EXAMPLE
    .\add-mcp-context7.ps1
    
.EXAMPLE
    .\add-mcp-context7.ps1 -Scope project -DryRun

.NOTES
    Exit codes:
      0 success
      1 generic error (missing prereq / command failure)
#>

[CmdletBinding()]
param(
    [Parameter()]
    [Alias('s')]
    [ValidateSet('local', 'user', 'project')]
    [string]$Scope = 'user',
    
    [Parameter()]
    [string]$McpName = 'context7-mcp',
    
    [Parameter()]
    [switch]$DryRun,
    
    [Parameter()]
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
$ScriptName = $MyInvocation.MyCommand.Name

# Color codes for output
$ColorDim = "`e[2m"
$ColorOk = "`e[32m"
$ColorWarn = "`e[33m"
$ColorErr = "`e[31m"
$ColorReset = "`e[0m"

function Write-Log {
    param([string]$Message)
    if (-not $Quiet) {
        Write-Host "${ColorDim}[${ScriptName}]${ColorReset} $Message"
    }
}

function Write-Ok {
    param([string]$Message)
    Write-Host "${ColorOk}[${ScriptName}]${ColorReset} $Message"
}

function Write-Warn {
    param([string]$Message)
    Write-Warning "${ColorWarn}[${ScriptName} WARN]${ColorReset} $Message"
}

function Write-Err {
    param([string]$Message)
    Write-Error "${ColorErr}[${ScriptName} ERROR]${ColorReset} $Message" -ErrorAction Continue
}

function Exit-WithError {
    param([string]$Message)
    Write-Err $Message
    exit 1
}

function Get-Runner {
    # context7-mcp is npm-only, no PyPI package available
    if (Get-Command bunx -ErrorAction SilentlyContinue) {
        return 'bunx'
    }
    elseif (Get-Command npx -ErrorAction SilentlyContinue) {
        return 'npx'
    }
    else {
        Exit-WithError "No suitable runner found (bunx or npx required; context7-mcp is npm-only)"
    }
}

function Test-ServerExists {
    try {
        $list = claude mcp list 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Warn "Could not list MCP servers (continuing)."
            return $false
        }
        # Match server name at start of line followed by colon
        return $list -match "^${McpName}:"
    }
    catch {
        Write-Warn "Could not list MCP servers (continuing)."
        return $false
    }
}

function Remove-Server {
    Write-Log "Removing existing $McpName (scope=$Scope)"
    
    if ($DryRun) {
        Write-Log "DRY-RUN: claude mcp remove -s $Scope $McpName"
        return
    }
    
    # Ignore errors - server may not exist
    try {
        $null = claude mcp remove -s $Scope $McpName 2>$null
    }
    catch {
        # Ignore
    }
}

function Add-Server {
    param([string]$Runner)
    
    Write-Log "Adding $McpName via $Runner (scope=$Scope)"
    
    # Build JSON config based on runner
    $jsonConfig = switch ($Runner) {
        'bunx' { '{"command":"bunx","args":["@upstash/context7-mcp"]}' }
        'npx'  { '{"command":"npx","args":["-y","@upstash/context7-mcp"]}' }
    }
    
    if ($DryRun) {
        Write-Log "DRY-RUN: claude mcp add-json -s $Scope $McpName '$jsonConfig'"
        return
    }
    
    & claude mcp add-json -s $Scope $McpName $jsonConfig
    if ($LASTEXITCODE -ne 0) {
        Exit-WithError "Failed to add $McpName server"
    }
}

# Main execution
try {
    # Check if claude CLI exists
    $claudeCmd = Get-Command claude -ErrorAction SilentlyContinue
    if (-not $claudeCmd) {
        Exit-WithError "'claude' CLI not found in PATH"
    }
    
    # Detect runner
    $runner = Get-Runner
    Write-Log "Using runner: $runner"
    
    # Always remove first to ensure clean overwrite
    Remove-Server
    
    Add-Server -Runner $runner
    
    $serverExists = Test-ServerExists
    if ($serverExists) {
        Write-Ok "$McpName configured successfully (scope=$Scope) using $runner"
    }
    else {
        if ($DryRun) {
            Write-Ok "DRY-RUN complete (no changes applied)"
        }
        else {
            Write-Warn "$McpName not detected after add (check 'claude mcp list')."
        }
    }
}
catch {
    Exit-WithError $_.Exception.Message
}
