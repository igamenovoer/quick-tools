<#
.SYNOPSIS
    Searches the Open VSX Registry for extensions.

.DESCRIPTION
    Uses the Open VSX API to search for extensions by keyword.
    Useful since the 'ovsx' CLI does not support search.

.PARAMETER Query
    The search term (e.g., "python", "theme").

.EXAMPLE
    .\search-openvsx.ps1 -Query "python"
    .\search-openvsx.ps1 "dracula"
#>

param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$Query,
    
    [int]$Limit = 10
)

$ApiUrl = "https://open-vsx.org/api/-/search?query=$([Uri]::EscapeDataString($Query))&size=$Limit"

try {
    Write-Host "Searching Open VSX for '$Query'..." -ForegroundColor Cyan
    $Response = Invoke-RestMethod -Uri $ApiUrl -Method Get -ErrorAction Stop

    if ($Response.extensions.Count -eq 0) {
        Write-Warning "No extensions found."
        exit
    }

    $Response.extensions | Select-Object `
        @{N='ID';E={$_.namespace + '.' + $_.name}}, `
        @{N='Version';E={$_.version}}, `
        @{N='Description';E={$_.description}} | Format-Table -AutoSize -Wrap
}
catch {
    Write-Error "Failed to search Open VSX: $_"
}
