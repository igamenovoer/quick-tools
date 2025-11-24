# Fix Podman machine SSH key permissions
# This script will automatically request administrator privileges if needed

# Check if running as administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "Requesting administrator privileges..."
    Start-Process pwsh -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

$keyPath = "$env:USERPROFILE\.local\share\containers\podman\machine\machine"

Write-Host "Fixing permissions for: $keyPath"

# Remove inheritance and all existing permissions
icacls.exe $keyPath /inheritance:r

# Grant only the current user read permissions
icacls.exe $keyPath /grant:r "$($env:USERNAME):(R)"

Write-Host "`nPermissions fixed. New permissions:"
icacls.exe $keyPath

Write-Host "`nYou can now run 'podman machine ssh' without password prompts."
