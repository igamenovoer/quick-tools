# Create docker.exe symlink to podman.exe
# This script requires administrator privileges
# Works with both PowerShell and CMD
# If not running as admin, will automatically elevate with UAC prompt

# Check if running as administrator
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "Not running as administrator. Requesting elevation..." -ForegroundColor Yellow
    
    # Re-launch the script with administrator privileges
    $scriptPath = $MyInvocation.MyCommand.Path
    $process = Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`"" -PassThru -Wait
    
    # Check the exit code from the elevated process
    if ($process.ExitCode -eq 0) {
        Write-Host "`nSymlink creation completed successfully!" -ForegroundColor Green
        Write-Host "Verifying 'docker' command works..." -ForegroundColor Cyan
        
        # Test if docker command works
        try {
            $dockerVersion = docker --version 2>&1
            Write-Host "docker --version: $dockerVersion" -ForegroundColor Green
            Write-Host "`nYou can now use 'docker' commands!" -ForegroundColor Green
        }
        catch {
            Write-Host "WARNING: docker command not found. You may need to restart your terminal." -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "`nERROR: Symlink creation failed (exit code: $($process.ExitCode))" -ForegroundColor Red
    }
    
    Write-Host "`nPress any key to exit..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit $process.ExitCode
}

Write-Host "Creating docker.exe symlink to podman.exe..." -ForegroundColor Cyan

# Find podman.exe location
$podmanPath = Get-Command podman -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source

if (-not $podmanPath) {
    Write-Host "ERROR: podman.exe not found in PATH" -ForegroundColor Red
    Write-Host "Please ensure Podman is installed and available in PATH" -ForegroundColor Yellow
    exit 1
}

Write-Host "Found podman at: $podmanPath" -ForegroundColor Green

# Get the directory where podman.exe is located
$podmanDir = Split-Path -Parent $podmanPath
$dockerPath = Join-Path $podmanDir "docker.exe"

# Check if docker.exe already exists
if (Test-Path $dockerPath) {
    Write-Host "WARNING: docker.exe already exists at $dockerPath" -ForegroundColor Yellow
    
    # Check if it's already a symlink to podman
    $existingItem = Get-Item $dockerPath
    if ($existingItem.LinkType -eq "SymbolicLink") {
        $target = $existingItem.Target
        Write-Host "It is a symbolic link pointing to: $target" -ForegroundColor Yellow
        
        if ($target -eq $podmanPath) {
            Write-Host "The symlink already points to podman.exe. Nothing to do." -ForegroundColor Green
            exit 0
        }
    }
    
    $response = Read-Host "Do you want to replace it? (y/N)"
    if ($response -ne 'y' -and $response -ne 'Y') {
        Write-Host "Aborted by user" -ForegroundColor Yellow
        exit 0
    }
    
    # Remove existing docker.exe
    Remove-Item $dockerPath -Force
    Write-Host "Removed existing docker.exe" -ForegroundColor Yellow
}

# Create symbolic link
try {
    New-Item -ItemType SymbolicLink -Path $dockerPath -Target $podmanPath -Force | Out-Null
    Write-Host "SUCCESS: Created symbolic link at $dockerPath -> $podmanPath" -ForegroundColor Green
    
    # Verify the symlink works
    Write-Host "`nVerifying the symlink..." -ForegroundColor Cyan
    $dockerVersion = & $dockerPath --version 2>&1
    Write-Host "docker --version output: $dockerVersion" -ForegroundColor Green
    
    Write-Host "`nYou can now use 'docker' command in place of 'podman'" -ForegroundColor Green
    Write-Host "Example: docker ps, docker images, docker run, etc." -ForegroundColor Cyan
    
    Write-Host "`nPress any key to exit..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 0
}
catch {
    Write-Host "ERROR: Failed to create symbolic link" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    
    Write-Host "`nPress any key to exit..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 1
}
