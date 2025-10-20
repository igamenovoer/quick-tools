# PowerShell script for Claude Code installation and configuration
# Exit on errors
$ErrorActionPreference = "Stop"

# --- Interactive Menu Function ---
function Show-Menu {
    param (
        [string[]]$Options,
        [int]$CurrentSelection = 0
    )
    
    $optionsCount = $Options.Count
    
    # Hide cursor
    [Console]::CursorVisible = $false
    
    try {
        while ($true) {
            # Clear previous menu
            $cursorTop = [Console]::CursorTop
            
            for ($i = 0; $i -lt $optionsCount; $i++) {
                if ($i -eq $CurrentSelection) {
                    Write-Host "  > $($Options[$i])" -ForegroundColor Green
                } else {
                    Write-Host "    $($Options[$i])"
                }
            }
            
            Write-Host "Use ↑/↓ to navigate, Enter to select｜使用 ↑/↓ 方向键选择，回车键确认" -ForegroundColor Yellow
            
            $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            
            # Move cursor back up
            [Console]::SetCursorPosition(0, $cursorTop)
            
            switch ($key.VirtualKeyCode) {
                38 { # Up arrow
                    $CurrentSelection = ($CurrentSelection - 1 + $optionsCount) % $optionsCount
                }
                40 { # Down arrow
                    $CurrentSelection = ($CurrentSelection + 1) % $optionsCount
                }
                13 { # Enter
                    # Clear menu
                    for ($i = 0; $i -lt $optionsCount + 1; $i++) {
                        Write-Host (" " * [Console]::WindowWidth)
                    }
                    [Console]::SetCursorPosition(0, $cursorTop)
                    return $CurrentSelection
                }
            }
        }
    }
    finally {
        [Console]::CursorVisible = $true
    }
}

# --- Install Node.js Function ---
function Install-NodeJS {
    Write-Host "🚀 Installing Node.js on Windows｜安装 Node.js..."
    
    $nvmVersion = "1.1.12"
    $nvmUrl = "https://github.com/coreybutler/nvm-windows/releases/download/$nvmVersion/nvm-setup.exe"
    $nvmInstaller = "$env:TEMP\nvm-setup.exe"
    
    Write-Host "📥 Downloading nvm-windows｜下载 nvm-windows..."
    try {
        Invoke-WebRequest -Uri $nvmUrl -OutFile $nvmInstaller -UseBasicParsing
        
        Write-Host "🔧 Please run the installer manually: $nvmInstaller｜请手动运行安装程序: $nvmInstaller"
        Write-Host "After installation, restart PowerShell and run this script again.｜安装完成后，请重启 PowerShell 并重新运行此脚本。"
        Start-Process $nvmInstaller -Wait
        
        Write-Host "🔄 Please restart PowerShell and run this script again.｜请重启 PowerShell 并重新运行此脚本。"
        exit 0
    }
    catch {
        Write-Host "❌ Failed to download nvm-windows. Please install Node.js manually from https://nodejs.org/｜下载 nvm-windows 失败，请从 https://nodejs.org/ 手动安装 Node.js"
        exit 1
    }
}

# --- Check Node.js ---
Write-Host "`n=== Checking Node.js Installation｜检查 Node.js 安装 ===" -ForegroundColor Cyan

try {
    $nodeVersion = node --version
    $majorVersion = [int]($nodeVersion -replace 'v(\d+)\..*', '$1')
    
    if ($majorVersion -ge 18) {
        Write-Host "✅ Node.js is already installed｜Node.js 已安装: $nodeVersion" -ForegroundColor Green
    }
    else {
        Write-Host "⚠️  Node.js $nodeVersion is installed but version < 18. Please upgrade manually.｜Node.js 版本过低，请手动升级。"
        Install-NodeJS
    }
}
catch {
    Write-Host "⚠️  Node.js not found. Installing｜Node.js 未安装，开始安装..."
    Install-NodeJS
}

# --- Check npm ---
try {
    $npmVersion = npm --version
    Write-Host "✅ npm version｜npm 版本: $npmVersion" -ForegroundColor Green
}
catch {
    Write-Host "❌ npm not found. Please install Node.js properly.｜npm 未找到，请正确安装 Node.js。"
    exit 1
}

# --- Claude Code Installation/Update ---
Write-Host "`n=== Checking Claude Code Installation｜检查 Claude Code 安装 ===" -ForegroundColor Cyan

$needsInstall = $false

try {
    $claudeCmd = Get-Command claude -ErrorAction SilentlyContinue
    if ($claudeCmd) {
        Write-Host "✅ Claude Code is already installed. Checking for updates...｜Claude Code 已安装，正在检查更新..."
        
        $outdatedInfo = npm outdated -g @anthropic-ai/claude-code 2>$null
        
        if ($outdatedInfo -and $outdatedInfo.Count -gt 1) {
            $lines = $outdatedInfo -split "`n"
            if ($lines.Count -ge 2) {
                $parts = $lines[1] -split '\s+'
                $currentVersion = $parts[1]
                $latestVersion = $parts[3]
                
                Write-Host "✨ A new version is available: $latestVersion (you have $currentVersion).｜检测到新版本: $latestVersion (当前版本: $currentVersion)。"
                $response = Read-Host "Do you want to upgrade? (y/N)｜是否要升级？(y/N)"
                
                if ($response -match '^[Yy]$') {
                    $needsInstall = $true
                }
                else {
                    Write-Host "👍 Skipping upgrade.｜跳过升级。"
                }
            }
        }
        else {
            $claudeVersion = claude --version 2>$null
            if ($claudeVersion) {
                $version = ($claudeVersion -split '/')[1]
                Write-Host "✅ You are running the latest version ($version).｜您正在运行最新版本 ($version)。"
            }
        }
    }
    else {
        Write-Host "⚠️  Claude Code not found.｜Claude Code 未安装。"
        $needsInstall = $true
    }
}
catch {
    Write-Host "⚠️  Claude Code not found or installation is broken.｜Claude Code 未安装或安装已损坏。"
    $needsInstall = $true
}

# --- Install/Update Claude Code ---
if ($needsInstall) {
    Write-Host "`n🔄 Preparing environment by cleaning up previous versions (if any)...｜正在清理旧版本以准备环境..." -ForegroundColor Yellow
    
    try {
        Write-Host "🔧 Attempting to uninstall existing Claude Code...｜尝试卸载现有 Claude Code..."
        npm uninstall -g @anthropic-ai/claude-code 2>$null
        Write-Host "✅ Previous version uninstalled successfully.｜旧版本卸载成功。" -ForegroundColor Green
    }
    catch {
        Write-Host "⚠️  No existing installation found or uninstall not needed.｜未发现现有安装或无需卸载。"
    }
    
    Write-Host "`n📦 Installing @anthropic-ai/claude-code...｜安装 @anthropic-ai/claude-code..." -ForegroundColor Cyan
    
    try {
        npm install -g @anthropic-ai/claude-code
        Write-Host "✅ Claude Code installed successfully.｜Claude Code 安装成功。" -ForegroundColor Green
    }
    catch {
        Write-Host "❌ Installation failed. Please check your npm permissions.｜安装失败，请检查 npm 权限。" -ForegroundColor Red
        exit 1
    }
}

# --- Configure Claude Code ---
Write-Host "`n=== Configuring Claude Code｜配置 Claude Code ===" -ForegroundColor Cyan

$configPath = Join-Path $env:USERPROFILE ".claude.json"
Write-Host "Configuring Claude Code to skip onboarding｜免除 Claude Code 的 onboarding 环节..."

try {
    $config = @{}
    if (Test-Path $configPath) {
        $config = Get-Content $configPath -Raw | ConvertFrom-Json -AsHashtable
    }
    $config.hasCompletedOnboarding = $true
    $config | ConvertTo-Json | Set-Content $configPath -Encoding UTF8
    Write-Host "✅ Configuration saved.｜配置已保存。" -ForegroundColor Green
}
catch {
    Write-Host "⚠️  Failed to update configuration, but continuing...｜配置更新失败，但继续执行..." -ForegroundColor Yellow
}

# --- Environment Variable Configuration ---
Write-Host "`n=== Configuring Environment Variables｜配置环境变量 ===" -ForegroundColor Cyan

$apiKey = ""

# Check if environment variable already exists
$existingApiKey = [System.Environment]::GetEnvironmentVariable("ANTHROPIC_API_KEY", "User")
$existingBaseUrl = [System.Environment]::GetEnvironmentVariable("ANTHROPIC_BASE_URL", "User")

if ($existingBaseUrl -eq "https://api.siliconflow.cn/" -and $existingApiKey) {
    Write-Host "`n✅ Detected existing configuration. Using saved API Key.｜检测到已有配置，将使用已保存的 API Key。" -ForegroundColor Green
    $apiKey = $existingApiKey
}

if ([string]::IsNullOrEmpty($apiKey)) {
    Write-Host "`n🔑 Please enter your SiliconCloud API Key｜设置你的 SiliconCloud API Key:"
    Write-Host "   You can get your API Key from｜可访问右边地址获取 API Key: https://cloud.siliconflow.cn/account/ak"
    Write-Host "   Note: The input is hidden for security. Please paste your API Key directly.｜注意：输入的内容不会显示在屏幕上，请直接输入"
    Write-Host ""
    
    $secureApiKey = Read-Host -AsSecureString
    $apiKey = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureApiKey))
    
    if ([string]::IsNullOrEmpty($apiKey)) {
        Write-Host "⚠️  API Key cannot be empty. Please run the script again.｜API Key 未正确设置，请重新运行脚本" -ForegroundColor Red
        exit 1
    }
}

# --- Model Selection ---
Write-Host "`n=== Model Selection｜模型选择 ===" -ForegroundColor Cyan
Write-Host "🤖 Please select a model to use｜请选择需要使用的模型:`n"

$modelOptions = @(
    "Pro/deepseek-ai/DeepSeek-V3.1-Terminus",
    "deepseek-ai/DeepSeek-V3.1-Terminus",
    "Pro/moonshotai/Kimi-K2-Instruct-0905",
    "moonshotai/Kimi-K2-Instruct-0905",
    "Qwen/Qwen3-Coder-480B-A35B-Instruct",
    "Qwen/Qwen3-Coder-30B-A3B-Instruct",
    "zai-org/GLM-4.5",
    "Custom (enter your own model)｜自定义 (手动输入模型)"
)

$selection = Show-Menu -Options $modelOptions

$selectedModel = ""
if ($selection -eq ($modelOptions.Count - 1)) {
    Write-Host "`n✍️ Please enter the custom model name｜请输入自定义模型名称:"
    $customModel = Read-Host
    
    if ([string]::IsNullOrEmpty($customModel)) {
        Write-Host "⚠️ Model name cannot be empty. Exiting.｜模型名称不能为空，脚本退出。" -ForegroundColor Red
        exit 1
    }
    $selectedModel = $customModel
}
else {
    $selectedModel = $modelOptions[$selection]
}

Write-Host "`n✅ You have selected｜已选择模型: $selectedModel" -ForegroundColor Green

# --- Update Environment Variables ---
Write-Host "`n📝 Updating environment variables...｜正在更新环境变量..." -ForegroundColor Cyan

try {
    [System.Environment]::SetEnvironmentVariable("ANTHROPIC_BASE_URL", "https://api.siliconflow.cn/", "User")
    [System.Environment]::SetEnvironmentVariable("ANTHROPIC_API_KEY", $apiKey, "User")
    [System.Environment]::SetEnvironmentVariable("ANTHROPIC_MODEL", $selectedModel, "User")
    
    # Also set for current session
    $env:ANTHROPIC_BASE_URL = "https://api.siliconflow.cn/"
    $env:ANTHROPIC_API_KEY = $apiKey
    $env:ANTHROPIC_MODEL = $selectedModel
    
    Write-Host "✅ Environment variables successfully updated.｜环境变量更新成功。" -ForegroundColor Green
}
catch {
    Write-Host "❌ Failed to update environment variables.｜环境变量更新失败。" -ForegroundColor Red
    exit 1
}

# --- Completion ---
Write-Host "`n🎉 Configuration completed successfully｜配置已完成 🎉" -ForegroundColor Green
Write-Host ""
Write-Host "🔄 Please restart your PowerShell terminal to load the new environment variables.｜请重启 PowerShell 终端以加载新的环境变量。"
Write-Host ""
Write-Host "🚀 Then you can start using Claude Code with｜使用下面命令进入 Claude Code:"
Write-Host "   claude" -ForegroundColor Cyan
Write-Host ""
