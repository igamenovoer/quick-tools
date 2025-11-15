param(
    [Parameter(Mandatory=$false)]
    [string]$TargetDir
)

# Check if running as administrator
function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# If not admin, restart as admin
if (-not (Test-Administrator)) {
    Write-Host "Administrator privileges required. Restarting as administrator..." -ForegroundColor Yellow
    
    $scriptPath = $MyInvocation.MyCommand.Path
    $arguments = "-NoExit -ExecutionPolicy Bypass -File `"$scriptPath`""
    
    if ($TargetDir) {
        $arguments += " -TargetDir `"$TargetDir`""
    }
    
    Start-Process powershell.exe -Verb RunAs -ArgumentList $arguments
    exit
}

Write-Host "=== Podman Storage Migration Script ===" -ForegroundColor Cyan
Write-Host ""

# Get target directory from user if not provided
if (-not $TargetDir) {
    $TargetDir = Read-Host "Enter target directory path (e.g., D:\Podman)"
    if ([string]::IsNullOrWhiteSpace($TargetDir)) {
        Write-Host "Error: Target directory cannot be empty" -ForegroundColor Red
        Write-Host ""
        Write-Host "Press any key to exit..." -ForegroundColor Yellow
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        exit 1
    }
}

# Validate and normalize path
$TargetDir = $TargetDir.TrimEnd('\')
Write-Host "Target directory: $TargetDir" -ForegroundColor Green
Write-Host ""

# Define source directory
$SourceDir = "$env:USERPROFILE\.local\share\containers"
Write-Host "Source directory: $SourceDir" -ForegroundColor Green
Write-Host ""

# Check if source exists and is not already a junction
if (Test-Path $SourceDir) {
    $item = Get-Item $SourceDir -Force
    if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
        Write-Host "Source directory is already a junction point!" -ForegroundColor Yellow
        Write-Host "Target: $($item.Target)" -ForegroundColor Yellow
        Write-Host ""
        $continue = Read-Host "Do you want to recreate the junction to a new target? (y/N)"
        if ($continue -ne 'y' -and $continue -ne 'Y') {
            Write-Host "Operation cancelled." -ForegroundColor Yellow
            Write-Host ""
            Write-Host "Press any key to exit..." -ForegroundColor Yellow
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            exit 0
        }
    }
}

# Confirm operation
Write-Host "This script will:" -ForegroundColor Cyan
Write-Host "  1. Stop Podman machine" -ForegroundColor White
Write-Host "  2. Create target directory: $TargetDir" -ForegroundColor White
Write-Host "  3. Move existing data from: $SourceDir" -ForegroundColor White
Write-Host "  4. Create junction link" -ForegroundColor White
Write-Host "  5. Start Podman machine" -ForegroundColor White
Write-Host ""
$confirm = Read-Host "Continue? (y/N)"
if ($confirm -ne 'y' -and $confirm -ne 'Y') {
    Write-Host "Operation cancelled." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Press any key to exit..." -ForegroundColor Yellow
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 0
}

Write-Host ""
Write-Host "Starting migration..." -ForegroundColor Cyan
Write-Host ""

# Step 1: Stop Podman machine and WSL
Write-Host "[1/5] Stopping Podman machine and WSL..." -ForegroundColor Yellow
try {
    $result = podman machine stop 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  ✓ Podman machine stopped" -ForegroundColor Green
    } else {
        Write-Host "  ! Warning: Failed to stop Podman machine (it may not be running)" -ForegroundColor Yellow
        Write-Host "  $result" -ForegroundColor DarkGray
    }
} catch {
    Write-Host "  ! Warning: Error stopping Podman machine: $_" -ForegroundColor Yellow
}

# Ensure WSL is fully shut down to release file locks
Write-Host "  Shutting down WSL..." -ForegroundColor White
try {
    wsl --shutdown 2>&1 | Out-Null
    Start-Sleep -Seconds 2
    Write-Host "  ✓ WSL shut down" -ForegroundColor Green
} catch {
    Write-Host "  ! Warning: Error shutting down WSL: $_" -ForegroundColor Yellow
}
Write-Host ""

# Step 2: Create target directory
Write-Host "[2/5] Creating target directory..." -ForegroundColor Yellow
try {
    if (-not (Test-Path $TargetDir)) {
        New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
        Write-Host "  ✓ Created: $TargetDir" -ForegroundColor Green
    } else {
        Write-Host "  ✓ Directory already exists: $TargetDir" -ForegroundColor Green
    }
} catch {
    Write-Host "  ✗ Error creating target directory: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "Press any key to exit..." -ForegroundColor Yellow
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 1
}
Write-Host ""

# Step 3: Move existing data
Write-Host "[3/5] Moving existing data..." -ForegroundColor Yellow
if (Test-Path $SourceDir) {
    try {
        # Check if it's a junction first
        $item = Get-Item $SourceDir -Force
        if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
            Write-Host "  ! Removing existing junction..." -ForegroundColor Yellow
            Remove-Item $SourceDir -Force
            Write-Host "  ✓ Junction removed" -ForegroundColor Green
        } else {
            # Move contents
            $items = Get-ChildItem $SourceDir -Force -ErrorAction SilentlyContinue
            if ($items.Count -gt 0) {
                Write-Host "  Moving $($items.Count) items..." -ForegroundColor White
                
                # Try to move each item individually to handle locked files
                $moved = 0
                $failed = 0
                foreach ($item in $items) {
                    try {
                        Move-Item $item.FullName $TargetDir -Force -ErrorAction Stop
                        $moved++
                    } catch {
                        $failed++
                        Write-Host "  ! Warning: Could not move $($item.Name): $($_.Exception.Message)" -ForegroundColor Yellow
                    }
                }
                
                Write-Host "  ✓ Moved $moved items" -ForegroundColor Green
                if ($failed -gt 0) {
                    Write-Host "  ! Warning: $failed items could not be moved (may be locked)" -ForegroundColor Yellow
                }
            } else {
                Write-Host "  ✓ No data to move" -ForegroundColor Green
            }
            
            # Try to remove source directory (may fail if files are still locked)
            try {
                # Wait a moment for file handles to release
                Start-Sleep -Seconds 1
                Remove-Item $SourceDir -Recurse -Force -ErrorAction Stop
                Write-Host "  ✓ Source directory removed" -ForegroundColor Green
            } catch {
                Write-Host "  ! Warning: Could not remove source directory completely" -ForegroundColor Yellow
                Write-Host "  ! Some files may still be locked. Attempting to create junction anyway..." -ForegroundColor Yellow
                
                # Try to remove just the unlocked parts
                Get-ChildItem $SourceDir -Recurse -Force -ErrorAction SilentlyContinue | 
                    Sort-Object FullName -Descending | 
                    ForEach-Object {
                        try {
                            Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
                        } catch {
                            # Ignore errors on locked files
                        }
                    }
                
                # Final attempt to remove the directory structure
                try {
                    Remove-Item $SourceDir -Recurse -Force -ErrorAction Stop
                    Write-Host "  ✓ Source directory cleaned up" -ForegroundColor Green
                } catch {
                    Write-Host "  ! Source directory still contains locked files - will be overwritten by junction" -ForegroundColor Yellow
                }
            }
        }
    } catch {
        Write-Host "  ✗ Error moving data: $_" -ForegroundColor Red
        Write-Host ""
        Write-Host "Press any key to exit..." -ForegroundColor Yellow
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        exit 1
    }
} else {
    Write-Host "  ✓ Source directory does not exist (fresh install)" -ForegroundColor Green
}
Write-Host ""

# Step 4: Create junction
Write-Host "[4/5] Creating junction link..." -ForegroundColor Yellow
try {
    # Ensure parent directory exists
    $parentDir = Split-Path $SourceDir -Parent
    if (-not (Test-Path $parentDir)) {
        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
    }
    
    # If source still exists (locked files), force remove with cmd
    if (Test-Path $SourceDir) {
        Write-Host "  Removing remaining directory structure..." -ForegroundColor White
        cmd /c "rmdir /s /q `"$SourceDir`"" 2>&1 | Out-Null
        Start-Sleep -Milliseconds 500
    }
    
    # Create junction
    $mklink = cmd /c "mklink /J `"$SourceDir`" `"$TargetDir`"" 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  ✓ Junction created: $SourceDir -> $TargetDir" -ForegroundColor Green
    } else {
        Write-Host "  ✗ Failed to create junction: $mklink" -ForegroundColor Red
        Write-Host ""
        Write-Host "Press any key to exit..." -ForegroundColor Yellow
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        exit 1
    }
} catch {
    Write-Host "  ✗ Error creating junction: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "Press any key to exit..." -ForegroundColor Yellow
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 1
}
Write-Host ""

# Step 5: Start Podman machine
Write-Host "[5/5] Starting Podman machine..." -ForegroundColor Yellow
try {
    $result = podman machine start 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  ✓ Podman machine started" -ForegroundColor Green
    } else {
        Write-Host "  ! Warning: Failed to start Podman machine" -ForegroundColor Yellow
        Write-Host "  You may need to start it manually with: podman machine start" -ForegroundColor Yellow
        Write-Host "  $result" -ForegroundColor DarkGray
    }
} catch {
    Write-Host "  ! Warning: Error starting Podman machine: $_" -ForegroundColor Yellow
    Write-Host "  You may need to start it manually with: podman machine start" -ForegroundColor Yellow
}
Write-Host ""

# Verify
Write-Host "=== Migration Complete ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Verification:" -ForegroundColor Yellow
Write-Host "  Junction: $SourceDir" -ForegroundColor White
Write-Host "  Target:   $TargetDir" -ForegroundColor White
Write-Host ""

# Show junction info
try {
    $junctionItem = Get-Item $SourceDir -Force
    if ($junctionItem.Target) {
        Write-Host "✓ Junction verified: $($junctionItem.Target)" -ForegroundColor Green
    }
} catch {
    Write-Host "! Could not verify junction" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "You can verify storage location with:" -ForegroundColor Cyan
Write-Host "  podman info | Select-String graphRoot" -ForegroundColor White
Write-Host ""
Write-Host "Press any key to exit..." -ForegroundColor Yellow
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
