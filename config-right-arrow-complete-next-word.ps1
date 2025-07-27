#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Configures PSReadLine Predictive IntelliSense to complete the next word with the Right-Arrow key.
.DESCRIPTION
    This script performs the following actions:
    1. Ensures PowerShell Gallery is trusted.
    2. Checks if PSReadLine version 2.1.0 or newer is installed, and installs/updates it if necessary.
    3. Enables history-based predictive IntelliSense.
    4. Configures the Right-Arrow key to accept the next word of a suggestion.
    5. Makes these settings permanent by adding them to the user's PowerShell profile.

    This script REQUIRES administrator privileges to run and will install modules system-wide.
.NOTES
    Author: GitHub Copilot
    Date: 2025-07-15
    Requires: Administrator privileges
#>

# Verify Administrator rights (double-check even with #Requires directive).
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "This script requires Administrator privileges to run."
    Write-Host "Please right-click on PowerShell and select 'Run as Administrator', then run this script again."
    Read-Host "Press Enter to exit"
    exit 1
} else {
    Write-Host "Running with Administrator privileges. Proceeding with system-wide configuration..."
}

# --- Configuration ---
$minPSReadLineVersion = '2.1.0'
$profilePath = $PROFILE.CurrentUserCurrentHost

# --- User Choice ---
$validChoice = $false
$choice = ''
while (-not $validChoice) {
    Write-Host "Select the desired behavior for the Right-Arrow key:"
    Write-Host "1) Complete only the next word of the suggestion."
    Write-Host "2) Complete the entire suggestion."
    $choice = Read-Host -Prompt "Enter your choice (1 or 2)"
    if ($choice -eq '1' -or $choice -eq '2') {
        $validChoice = $true
    } else {
        Write-Warning "Invalid input. Please enter 1 or 2."
    }
}

# --- Script Block for Key Handler ---
$keyHandlerScriptBlock = if ($choice -eq '1') {
    # Option 1: Complete next word
    {
        $line = $null
        $cursor = $null
        [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

        if ($cursor -lt $line.Length) {
            [Microsoft.PowerShell.PSConsoleReadLine]::ForwardChar()
        }
        else {
            [Microsoft.PowerShell.PSConsoleReadLine]::AcceptNextSuggestionWord()
        }
    }
}
else {
    # Option 2: Complete whole suggestion
    {
        $line = $null
        $cursor = $null
        [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

        if ($cursor -lt $line.Length) {
            [Microsoft.PowerShell.PSConsoleReadLine]::ForwardChar()
        }
        else {
            [Microsoft.PowerShell.PSConsoleReadLine]::AcceptSuggestion()
        }
    }
}


# Convert the script block to a string for storing in the profile
$keyHandlerString = $keyHandlerScriptBlock.ToString()

# --- Main Logic ---

try {
    Write-Host "Step 1: Checking PowerShell Gallery repository..."
    # Ensure PowerShell Gallery is set as trusted system-wide
    $gallery = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
    if ($gallery -and $gallery.InstallationPolicy -ne 'Trusted') {
        Write-Host "Setting PowerShell Gallery as trusted system-wide..."
        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
    }

    Write-Host "Step 2: Checking PSReadLine version..."
    $psReadLineModule = Get-Module -Name PSReadLine -ListAvailable | Where-Object { $_.Version -ge $minPSReadLineVersion } | Select-Object -First 1

    if (-not $psReadLineModule) {
        Write-Host "PSReadLine version $minPSReadLineVersion or newer not found. Installing/updating system-wide..."
        try {
            # Install system-wide (requires admin privileges)
            Install-Module -Name PSReadLine -MinimumVersion $minPSReadLineVersion -Repository PSGallery -Force -AllowClobber -ErrorAction Stop
            Write-Host "PSReadLine has been installed/updated successfully system-wide."
            # Import the module to use it in the current session
            Import-Module PSReadLine -Force
        }
        catch {
            Write-Error "Failed to install PSReadLine: $($_.Exception.Message)"
            Write-Host "Please try running the following command manually as Administrator:"
            Write-Host "Install-Module -Name PSReadLine -MinimumVersion $minPSReadLineVersion -Repository PSGallery -Force -AllowClobber"
            exit 1
        }
    } else {
        Write-Host "PSReadLine version $($psReadLineModule.Version) is installed."
    }

    Write-Host "Step 3: Enabling Predictive IntelliSense from history..."
    Set-PSReadLineOption -PredictionSource History
    Write-Host "Prediction source set to 'History'."

    Write-Host "Step 4: Configuring Right-Arrow key for next word completion..."
    Set-PSReadLineKeyHandler -Key RightArrow -ScriptBlock $keyHandlerScriptBlock
    Write-Host "Right-Arrow key handler configured for the current session."

    Write-Host "Step 5: Making configuration permanent in PowerShell profile..."
    # Ensure profile file exists
    if (-not (Test-Path -Path $profilePath)) {
        Write-Host "Profile file not found at '$profilePath'. Creating it."
        New-Item -Path $profilePath -ItemType File -Force | Out-Null
    }

    $profileContent = Get-Content -Path $profilePath -Raw

    # --- Manage Prediction Source Setting in Profile ---
    $predictionSourceSetting = "Set-PSReadLineOption -PredictionSource History"
    $predictionSourceBlockStart = "# BEGIN: Enable Predictive IntelliSense"
    $predictionSourceBlockEnd = "# END: Enable Predictive IntelliSense"

    if ($profileContent -match "(?s)$([regex]::Escape($predictionSourceBlockStart)).*?$([regex]::Escape($predictionSourceBlockEnd))") {
        # Remove existing block to replace it
        $profileContent = $profileContent -replace "(?s)$([regex]::Escape($predictionSourceBlockStart)).*?$([regex]::Escape($predictionSourceBlockEnd))", ''
        Set-Content -Path $profilePath -Value $profileContent.Trim() -Force
        Write-Host "Removed old prediction source setting from profile."
    }

    Write-Host "Adding prediction source setting to profile."
    $predictionBlock = @"

$predictionSourceBlockStart
$predictionSourceSetting
$predictionSourceBlockEnd
"@
    Add-Content -Path $profilePath -Value $predictionBlock


    # --- Manage Key Handler Setting in Profile ---
    $keyHandlerBlockStart = "# BEGIN: RightArrow Key Handler Configuration"
    $keyHandlerBlockEnd = "# END: RightArrow Key Handler Configuration"

    # Check for and remove the old configuration block
    if ($profileContent -match "(?s)$([regex]::Escape($keyHandlerBlockStart)).*?$([regex]::Escape($keyHandlerBlockEnd))") {
        $profileContent = $profileContent -replace "(?s)$([regex]::Escape($keyHandlerBlockStart)).*?$([regex]::Escape($keyHandlerBlockEnd))", ''
        Set-Content -Path $profilePath -Value $profileContent.Trim() -Force
        Write-Host "Removed old Right-Arrow key handler configuration from profile."
    }

    # Add the new configuration block
    Write-Host "Adding new Right-Arrow key handler to profile."
    $fullKeyHandlerBlock = @"

$keyHandlerBlockStart
# Configures the Right-Arrow key based on user selection.
Set-PSReadLineKeyHandler -Key RightArrow -ScriptBlock {
$keyHandlerString
}
$keyHandlerBlockEnd
"@
    Add-Content -Path $profilePath -Value $fullKeyHandlerBlock


    Write-Host "`nConfiguration complete!"
    Write-Host "Please restart your PowerShell session for the permanent changes to take effect."

}
catch {
    Write-Error "An error occurred: $_"
    exit 1
}
