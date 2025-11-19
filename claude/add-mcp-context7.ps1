#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Ensure the Context7 MCP server is configured for Claude Code.

.DESCRIPTION
    add-mcp-context7.ps1
    If the server already exists under the chosen scope, it is removed first, then re-added.
    
    Default behavior: scope = user
    Command used to add:
      claude mcp add -s user context7-mcp -- npx -y @upstash/context7-mcp

.PARAMETER Scope
    Override scope (default: user). Valid values: user, global

.PARAMETER DryRun
    Show actions without executing

.PARAMETER NoReplace
    Skip re-adding if already present (exit 0)

.PARAMETER Force
    Continue even if removal reports not found

.PARAMETER Quiet
    Less output

.EXAMPLE
    .\add-mcp-context7.ps1
    
.EXAMPLE
    .\add-mcp-context7.ps1 -Scope global -DryRun

.NOTES
    Exit codes:
      0 success
      1 generic error (missing prereq / command failure)
#>

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet('user', 'global')]
    [string]$Scope = 'user',
    
    [Parameter()]
    [switch]$DryRun,
    
    [Parameter()]
    [switch]$NoReplace,
    
    [Parameter()]
    [switch]$Force,
    
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

function Test-ServerExists {
    try {
        $list = claude mcp list 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Warn "Could not list MCP servers (continuing)."
            return $false
        }
        # Simple substring match
        return $list -match '(^|[\s])context7-mcp(\s|$)'
    }
    catch {
        Write-Warn "Could not list MCP servers (continuing)."
        return $false
    }
}

function Remove-Server {
    Write-Log "Removing existing context7-mcp (scope=$Scope)"
    
    if ($DryRun) {
        Write-Log "DRY-RUN: claude mcp remove -s $Scope context7-mcp"
        return
    }
    
    try {
        $output = claude mcp remove -s $Scope context7-mcp 2>&1
        if ($LASTEXITCODE -ne 0) {
            if ($Force) {
                Write-Warn "Removal reported an issue; continuing due to -Force"
            }
            else {
                Write-Warn "Removal failed; continuing to add anyway"
            }
        }
    }
    catch {
        if ($Force) {
            Write-Warn "Removal reported an issue; continuing due to -Force"
        }
        else {
            Write-Warn "Removal failed; continuing to add anyway"
        }
    }
}

function Add-Server {
    Write-Log "Adding context7-mcp via npx (scope=$Scope)"
    
    if ($DryRun) {
        Write-Log "DRY-RUN: claude mcp add -s $Scope context7-mcp -- npx -y @upstash/context7-mcp"
        return
    }
    
    # Note: The -- separates claude options from the npx command
    # Everything after -- is the actual command to run
    # Using & call operator and proper argument separation for PowerShell
    & claude mcp add -s $Scope context7-mcp '--' npx -y '@upstash/context7-mcp'
    if ($LASTEXITCODE -ne 0) {
        Exit-WithError "Failed to add context7-mcp server"
    }
}

# Main execution
try {
    # Check if claude CLI exists
    $claudeCmd = Get-Command claude -ErrorAction SilentlyContinue
    if (-not $claudeCmd) {
        Exit-WithError "'claude' CLI not found in PATH"
    }
    
    $serverExists = Test-ServerExists
    
    if ($serverExists) {
        if ($NoReplace) {
            Write-Ok "context7-mcp already present (scope=$Scope); skipping due to -NoReplace"
            exit 0
        }
        Remove-Server
    }
    else {
        Write-Log "context7-mcp not currently configured for scope=$Scope"
    }
    
    Add-Server
    
    $serverExists = Test-ServerExists
    if ($serverExists) {
        Write-Ok "context7-mcp configured successfully (scope=$Scope)"
    }
    else {
        if ($DryRun) {
            Write-Ok "DRY-RUN complete (no changes applied)"
        }
        else {
            Write-Warn "context7-mcp not detected after add (check 'claude mcp list')."
        }
    }
}
catch {
    Exit-WithError $_.Exception.Message
}
