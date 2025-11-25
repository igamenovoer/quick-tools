<#
.SYNOPSIS
    Automated test script for VS Code offline installation in Docker environment.

.DESCRIPTION
    This script automates the testing workflow:
    1. Starts the Docker test container
    2. Waits for SSH to be ready
    3. Runs the installation script
    4. Verifies the installation
    5. Reports results

.PARAMETER SkipDownload
    Skip downloading VS Code package (use existing test-package directory).

.EXAMPLE
    .\test-docker-env.ps1

.EXAMPLE
    .\test-docker-env.ps1 -SkipDownload
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [switch]$SkipDownload
)

$ErrorActionPreference = "Stop"

Write-Host "`n╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  VS Code Offline Installation - Docker Test Automation    ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

$dockerDir = Join-Path $PSScriptRoot "dockers"
$packageDir = Join-Path $PSScriptRoot "test-package"
$sshHost = "testuser@localhost"
$sshPort = 4444
$sshPassword = "123456"

# Test results
$testResults = @{
    DockerStart = $false
    SSHConnectivity = $false
    NetworkIsolation = $false
    VSCodeInstall = $false
    InstallVerification = $false
}

# Function to test SSH connectivity
function Test-SSHConnection {
    param([string]$HostTarget, [int]$Port, [int]$Timeout = 30)
    
    Write-Host "Testing SSH connectivity to ${HostTarget}:${Port}..." -ForegroundColor Yellow
    $startTime = Get-Date
    
    while (((Get-Date) - $startTime).TotalSeconds -lt $Timeout) {
        try {
            $null = & ssh -p $Port -o ConnectTimeout=2 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $HostTarget "exit" 2>&1
            if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq 255) {
                Write-Host "  ✓ SSH is accessible" -ForegroundColor Green
                return $true
            }
        }
        catch {
            # Ignore errors, keep trying
        }
        
        Start-Sleep -Seconds 2
    }
    
    Write-Host "  ✗ SSH timeout after $Timeout seconds" -ForegroundColor Red
    return $false
}

# Step 1: Start Docker container
Write-Host "════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "Step 1: Starting Docker Container" -ForegroundColor Cyan
Write-Host "════════════════════════════════════════`n" -ForegroundColor Cyan

Push-Location $dockerDir
try {
    Write-Host "Stopping any existing container..." -ForegroundColor Yellow
    & docker-compose down 2>&1 | Out-Null
    
    Write-Host "Starting fresh container..." -ForegroundColor Yellow
    $output = & docker-compose up -d 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  ✓ Container started successfully" -ForegroundColor Green
        $testResults.DockerStart = $true
        
        # Show container info
        Start-Sleep -Seconds 2
        $containerInfo = & docker-compose ps 2>&1
        Write-Host "`nContainer Status:" -ForegroundColor Cyan
        Write-Host $containerInfo -ForegroundColor White
    }
    else {
        Write-Host "  ✗ Failed to start container" -ForegroundColor Red
        Write-Host $output -ForegroundColor Red
        exit 1
    }
}
finally {
    Pop-Location
}

Write-Host ""

# Step 2: Wait for SSH to be ready
Write-Host "════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "Step 2: Waiting for SSH Service" -ForegroundColor Cyan
Write-Host "════════════════════════════════════════`n" -ForegroundColor Cyan

if (Test-SSHConnection -Host $sshHost -Port $sshPort -Timeout 30) {
    $testResults.SSHConnectivity = $true
}
else {
    Write-Host "✗ SSH service not available. Check Docker logs:" -ForegroundColor Red
    Write-Host "  docker-compose -f $dockerDir\docker-compose.yaml logs" -ForegroundColor Yellow
    exit 1
}

Write-Host ""

# Step 3: Verify network isolation
Write-Host "════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "Step 3: Verifying Network Isolation" -ForegroundColor Cyan
Write-Host "════════════════════════════════════════`n" -ForegroundColor Cyan

Write-Host "Testing internet connectivity (should fail)..." -ForegroundColor Yellow
$null = & docker exec vscode-test-ubuntu ping -c 1 -W 2 8.8.8.8 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "  ✓ Network is properly isolated (no internet access)" -ForegroundColor Green
    $testResults.NetworkIsolation = $true
}
else {
    Write-Host "  ✗ WARNING: Container has internet access!" -ForegroundColor Red
    Write-Host "  This may affect test accuracy." -ForegroundColor Yellow
}

Write-Host ""

# Step 4: Download VS Code package (if needed)
if (-not $SkipDownload) {
    Write-Host "════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "Step 4: Downloading VS Code Package" -ForegroundColor Cyan
    Write-Host "════════════════════════════════════════`n" -ForegroundColor Cyan
    
    if (Test-Path $packageDir) {
        Write-Host "Removing old package directory..." -ForegroundColor Yellow
        Remove-Item -Path $packageDir -Recurse -Force
    }
    
    Write-Host "Downloading latest VS Code package..." -ForegroundColor Yellow
    & "$PSScriptRoot\download-latest-vscode-package.ps1" -Output $packageDir
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "✗ Download failed" -ForegroundColor Red
        exit 1
    }
    
    Write-Host ""
}
else {
    Write-Host "════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "Step 4: Skipping Download (using existing package)" -ForegroundColor Cyan
    Write-Host "════════════════════════════════════════`n" -ForegroundColor Cyan
    
    if (-not (Test-Path $packageDir)) {
        Write-Host "✗ Package directory not found: $packageDir" -ForegroundColor Red
        Write-Host "  Run without -SkipDownload to download the package." -ForegroundColor Yellow
        exit 1
    }
    
    Write-Host "  ✓ Using package from: $packageDir" -ForegroundColor Green
    Write-Host ""
}

# Step 5: Install VS Code Server
Write-Host "════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "Step 5: Installing VS Code Server" -ForegroundColor Cyan
Write-Host "════════════════════════════════════════`n" -ForegroundColor Cyan

Write-Host "Running install-remote.ps1..." -ForegroundColor Yellow
try {
    & "$PSScriptRoot\install-remote.ps1" `
        -OfflinePackageDir $packageDir `
        -SshHost $sshHost `
        -SshPort $sshPort `
        -SshPassword $sshPassword `
        -Arch "x64"
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "`n  ✓ Installation completed successfully" -ForegroundColor Green
        $testResults.VSCodeInstall = $true
    }
    else {
        Write-Host "`n  ✗ Installation failed" -ForegroundColor Red
    }
}
catch {
    Write-Host "`n  ✗ Installation error: $_" -ForegroundColor Red
}

Write-Host ""

# Step 6: Verify installation
Write-Host "════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "Step 6: Verifying Installation" -ForegroundColor Cyan
Write-Host "════════════════════════════════════════`n" -ForegroundColor Cyan

Write-Host "Checking VS Code Server files..." -ForegroundColor Yellow
$verifyScript = @"
if [ -d "\$HOME/.vscode-server/cli/servers" ]; then
    echo "Found VS Code Server installations:"
    ls -1 "\$HOME/.vscode-server/cli/servers/" | head -5
    exit 0
else
    echo "VS Code Server directory not found"
    exit 1
fi
"@

$verifyResult = & docker exec -u testuser vscode-test-ubuntu bash -c $verifyScript 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "  ✓ VS Code Server verified" -ForegroundColor Green
    Write-Host $verifyResult -ForegroundColor White
    $testResults.InstallVerification = $true
}
else {
    Write-Host "  ✗ Verification failed" -ForegroundColor Red
    Write-Host $verifyResult -ForegroundColor Red
}

Write-Host ""

# Summary
Write-Host "════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "Test Summary" -ForegroundColor Cyan
Write-Host "════════════════════════════════════════`n" -ForegroundColor Cyan

$passCount = 0
$totalCount = $testResults.Count

foreach ($test in $testResults.GetEnumerator()) {
    $status = if ($test.Value) { "✓ PASS" } else { "✗ FAIL" }
    $color = if ($test.Value) { "Green" } else { "Red" }
    
    Write-Host "$status - $($test.Key)" -ForegroundColor $color
    
    if ($test.Value) { $passCount++ }
}

Write-Host "`nResults: $passCount/$totalCount tests passed" -ForegroundColor $(if ($passCount -eq $totalCount) { "Green" } else { "Yellow" })

if ($passCount -eq $totalCount) {
    Write-Host "`n🎉 All tests passed! Your Docker test environment is ready." -ForegroundColor Green
    Write-Host "`nNext steps:" -ForegroundColor Cyan
    Write-Host "  1. Connect from VS Code using Remote-SSH" -ForegroundColor White
    Write-Host "     F1 → Remote-SSH: Connect to Host" -ForegroundColor White
    Write-Host "     Enter: ssh -p 4444 testuser@localhost" -ForegroundColor Yellow
    Write-Host "  2. Password: 123456" -ForegroundColor White
}
else {
    Write-Host "`n⚠️  Some tests failed. Review the output above." -ForegroundColor Yellow
    Write-Host "`nTroubleshooting:" -ForegroundColor Cyan
    Write-Host "  • Check Docker logs: docker-compose -f $dockerDir\docker-compose.yaml logs" -ForegroundColor White
    Write-Host "  • Verify container status: docker-compose -f $dockerDir\docker-compose.yaml ps" -ForegroundColor White
    Write-Host "  • Manual SSH test: ssh -p $sshPort $sshHost" -ForegroundColor White
}

Write-Host ""
