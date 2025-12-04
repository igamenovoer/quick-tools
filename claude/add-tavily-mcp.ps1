#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Ensure the Tavily MCP server is configured for Claude Code.

.DESCRIPTION
    add-tavily-mcp.ps1
    If the server already exists under the chosen scope, it is removed first, then re-added.
    
    Default behavior: scope = user, mcp-name = tavily
    Runner preference: bunx > npx > uvx (picks first available)
    Command used to add (example with npx):
      claude mcp add-json -s user tavily '{"command":"npx","args":["-y","tavily-mcp@latest"],"env":{"TAVILY_API_KEY":"..."}}'

.PARAMETER Scope
    Override scope: local, user, or project (default: user)

.PARAMETER McpName
    Override MCP server name (default: tavily)

.PARAMETER DryRun
    Show actions without executing

.PARAMETER NoReplace
    Skip re-adding if already present (exit 0)

.PARAMETER Force
    Continue even if removal reports not found

.PARAMETER Quiet
    Less output

.EXAMPLE
    .\add-tavily-mcp.ps1
    
.EXAMPLE
    .\add-tavily-mcp.ps1 -Scope local -McpName tavily-local

.EXAMPLE
    .\add-tavily-mcp.ps1 -s project -DryRun

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
    [string]$McpName = 'tavily',
    
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

# Detect runner: bunx > npx > uvx
function Get-Runner {
    if (Get-Command bunx -ErrorAction SilentlyContinue) {
        return "bunx"
    }
    elseif (Get-Command npx -ErrorAction SilentlyContinue) {
        return "npx"
    }
    elseif (Get-Command uvx -ErrorAction SilentlyContinue) {
        return "uvx"
    }
    else {
        Exit-WithError "No suitable runner found (bunx, npx, or uvx required)"
    }
}

# Get Tavily API key: check env first, then prompt user
function Get-TavilyApiKey {
    $envKey = $env:TAVILY_API_KEY
    if ($envKey) {
        Write-Log "TAVILY_API_KEY found in environment"
        return $envKey
    }
    else {
        Write-Log "TAVILY_API_KEY not found in environment, prompting user..."
        Write-Host ""
        Write-Host "Tavily API key is required. Get one at: https://app.tavily.com/home"
        $apiKey = Read-Host "Enter your Tavily API key"
        if ([string]::IsNullOrWhiteSpace($apiKey)) {
            Exit-WithError "Tavily API key cannot be empty"
        }
        return $apiKey
    }
}

function Test-ServerExists {
    try {
        $list = claude mcp list 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Warn "Could not list MCP servers (continuing)."
            return $false
        }
        # Check if MCP name appears in list
        return $list -match "(^|[\s:])$([regex]::Escape($McpName))([\s:]|$)"
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
    
    try {
        $output = claude mcp remove -s $Scope $McpName 2>&1
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
    param([string]$ApiKey)
    
    Write-Log "Adding $McpName via $Runner (scope=$Scope)"
    
    # Build JSON config based on runner
    $jsonConfig = switch ($Runner) {
        "bunx" {
            @{
                command = "bunx"
                args = @("tavily-mcp@latest")
                env = @{ TAVILY_API_KEY = $ApiKey }
            } | ConvertTo-Json -Compress
        }
        "npx" {
            @{
                command = "npx"
                args = @("-y", "tavily-mcp@latest")
                env = @{ TAVILY_API_KEY = $ApiKey }
            } | ConvertTo-Json -Compress
        }
        "uvx" {
            @{
                command = "uvx"
                args = @("tavily-mcp")
                env = @{ TAVILY_API_KEY = $ApiKey }
            } | ConvertTo-Json -Compress
        }
    }
    
    if ($DryRun) {
        Write-Log "DRY-RUN: claude mcp add-json -s $Scope $McpName '$jsonConfig'"
        return
    }
    
    # Run the command
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
    $Runner = Get-Runner
    Write-Log "Using runner: $Runner"
    
    # Get API key first
    $apiKey = Get-TavilyApiKey
    
    $serverExists = Test-ServerExists
    
    if ($serverExists) {
        if ($NoReplace) {
            Write-Ok "$McpName already present (scope=$Scope); skipping due to -NoReplace"
            exit 0
        }
        Remove-Server
    }
    else {
        Write-Log "$McpName not currently configured for scope=$Scope"
    }
    
    Add-Server -ApiKey $apiKey
    
    $serverExists = Test-ServerExists
    if ($serverExists) {
        Write-Ok "$McpName configured successfully (scope=$Scope) using $Runner"
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
