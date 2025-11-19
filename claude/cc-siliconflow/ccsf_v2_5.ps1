# PowerShell script for Windows
# Stop on errors
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
    
    # Save initial cursor position
    $startTop = [Console]::CursorTop
    
    # Reserve space for menu
    for ($i = 0; $i -lt ($optionsCount + 1); $i++) {
        Write-Host ""
    }
    [Console]::SetCursorPosition(0, $startTop)
    
    $key = $null
    while ($true) {
        # Reset cursor to menu start
        [Console]::SetCursorPosition(0, $startTop)
        
        # Display menu options
        for ($i = 0; $i -lt $optionsCount; $i++) {
            if ($i -eq $CurrentSelection) {
                Write-Host "  > $($Options[$i])" -ForegroundColor Cyan
            } else {
                Write-Host "    $($Options[$i])"
            }
        }
        
        Write-Host "Use ↑/↓ to navigate, Enter to select｜使用 ↑/↓ 方向键选择，回车键确认" -ForegroundColor Yellow
        
        # Read key
        $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        
        switch ($key.VirtualKeyCode) {
            38 { # Up arrow
                $CurrentSelection = ($CurrentSelection - 1 + $optionsCount) % $optionsCount
            }
            40 { # Down arrow
                $CurrentSelection = ($CurrentSelection + 1) % $optionsCount
            }
            13 { # Enter
                # Clear menu
                [Console]::SetCursorPosition(0, $startTop)
                for ($i = 0; $i -lt ($optionsCount + 1); $i++) {
                    Write-Host (" " * [Console]::WindowWidth)
                }
                [Console]::SetCursorPosition(0, $startTop)
                [Console]::CursorVisible = $true
                return $CurrentSelection
            }
        }
    }
}

# Function to check if running as administrator
function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Function to install Node.js using winget
function Install-NodeJS {
    Write-Host "🚀 Installing Node.js on Windows｜安装 Node.js..." -ForegroundColor Green
    
    # Check if winget is available
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Host "❌ winget is not available. Please install App Installer from Microsoft Store.｜winget 不可用，请从微软商店安装应用安装程序。" -ForegroundColor Red
        Write-Host "💡 Or install Node.js manually from https://nodejs.org/｜或从 https://nodejs.org/ 手动安装" -ForegroundColor Yellow
        exit 1
    }
    
    Write-Host "📦 Installing Node.js using winget...｜使用 winget 安装 Node.js..."
    try {
        winget install -e --id OpenJS.NodeJS --silent --accept-source-agreements --accept-package-agreements
        Write-Host "✅ Node.js installation completed!｜Node.js 安装完成！" -ForegroundColor Green
        
        # Refresh environment variables
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
        
        Write-Host "✅ Node.js version｜Node.js 版本: $(node -v)" -ForegroundColor Green
        Write-Host "✅ npm version｜npm 版本: $(npm -v)" -ForegroundColor Green
    } catch {
        Write-Host "❌ Installation failed. Please try manually: winget install OpenJS.NodeJS｜安装失败，请手动尝试：winget install OpenJS.NodeJS" -ForegroundColor Red
        exit 1
    }
}

# Check Node.js installation
Write-Host ""
if (Get-Command node -ErrorAction SilentlyContinue) {
    $nodeVersion = (node -v) -replace 'v', ''
    $majorVersion = [int]($nodeVersion -split '\.')[0]
    
    if ($majorVersion -ge 18) {
        Write-Host "✅ Node.js is already installed｜Node.js 已安装: v$nodeVersion" -ForegroundColor Green
    } else {
        Write-Host "⚠️  Node.js v$nodeVersion is installed but version < 18. Upgrading...｜Node.js 版本升级中..." -ForegroundColor Yellow
        Install-NodeJS
    }
} else {
    Write-Host "❌ Node.js not found. Installing...｜Node.js 未安装，开始安装..." -ForegroundColor Yellow
    Install-NodeJS
}

# --- Check and Install/Update Claude Code ---
Write-Host ""
$needsInstall = $false

if (Get-Command claude -ErrorAction SilentlyContinue) {
    Write-Host "✅ Claude Code is already installed. Checking for updates...｜Claude Code 已安装，正在检查更新..." -ForegroundColor Green
    
    try {
        $outdatedInfo = npm outdated -g @anthropic-ai/claude-code 2>&1
        
        if ($outdatedInfo -match '@anthropic-ai/claude-code') {
            $lines = $outdatedInfo -split "`n"
            $packageLine = $lines | Where-Object { $_ -match '@anthropic-ai/claude-code' } | Select-Object -First 1
            $parts = $packageLine -split '\s+'
            
            if ($parts.Count -ge 4) {
                $currentVersion = $parts[1]
                $latestVersion = $parts[3]
                
                Write-Host "✨ A new version is available: $latestVersion (you have $currentVersion)." -ForegroundColor Cyan
                Write-Host "✨ 检测到新版本: $latestVersion (当前版本: $currentVersion)。" -ForegroundColor Cyan
                
                $response = Read-Host "Do you want to upgrade? (y/N)｜是否要升级？(y/N)"
                if ($response -match '^[Yy]$') {
                    $needsInstall = $true
                } else {
                    Write-Host "👍 Skipping upgrade.｜跳过升级。" -ForegroundColor Green
                }
            }
        } else {
            $currentVersion = (claude --version).Split('/')[1]
            Write-Host "✅ You are running the latest version ($currentVersion).｜您正在运行最新版本 ($currentVersion)。" -ForegroundColor Green
        }
    } catch {
        Write-Host "⚠️  Unable to check for updates. Continuing...｜无法检查更新，继续..." -ForegroundColor Yellow
    }
} else {
    Write-Host "❌ Claude Code not found or installation is broken.｜Claude Code 未安装或安装已损坏。" -ForegroundColor Yellow
    $needsInstall = $true
}

# Install or update Claude Code
if ($needsInstall) {
    Write-Host ""
    Write-Host "🔄 Preparing environment...｜正在准备环境..." -ForegroundColor Cyan
    
    # Try to uninstall existing version
    try {
        $existing = npm list -g @anthropic-ai/claude-code 2>&1
        if ($existing -match '@anthropic-ai/claude-code') {
            Write-Host "🔧 Uninstalling existing Claude Code...｜卸载现有 Claude Code..." -ForegroundColor Yellow
            npm uninstall -g @anthropic-ai/claude-code
            Write-Host "✅ Previous version uninstalled.｜旧版本已卸载。" -ForegroundColor Green
        }
    } catch {
        Write-Host "⚠️  No existing installation found or uninstall failed. Continuing...｜未发现现有安装或卸载失败，继续..." -ForegroundColor Yellow
    }
    
    Write-Host "📦 Installing @anthropic-ai/claude-code...｜安装 @anthropic-ai/claude-code..." -ForegroundColor Cyan
    
    try {
        npm install -g @anthropic-ai/claude-code
        Write-Host "✅ Claude Code installed successfully.｜Claude Code 安装成功。" -ForegroundColor Green
    } catch {
        Write-Host "❌ Installation failed. Please check npm permissions.｜安装失败，请检查 npm 权限。" -ForegroundColor Red
        Write-Host "💡 Try running PowerShell as Administrator｜尝试以管理员身份运行 PowerShell" -ForegroundColor Yellow
        exit 1
    }
}

# Configure Claude Code
Write-Host ""
Write-Host "⚙️  Configuring Claude Code to skip onboarding...｜配置 Claude Code 跳过引导..." -ForegroundColor Cyan

$configPath = Join-Path $env:USERPROFILE ".claude.json"
$config = @{}

if (Test-Path $configPath) {
    try {
        $config = Get-Content $configPath -Raw | ConvertFrom-Json -AsHashtable
    } catch {
        $config = @{}
    }
}

$config["hasCompletedOnboarding"] = $true
$config | ConvertTo-Json | Set-Content $configPath -Encoding UTF8

Write-Host "✅ Configuration completed.｜配置完成。" -ForegroundColor Green

# --- Environment Variables Check ---
Write-Host ""
$apiKey = ""
$existingKey = [System.Environment]::GetEnvironmentVariable("ANTHROPIC_API_KEY", "User")
$existingBaseUrl = [System.Environment]::GetEnvironmentVariable("ANTHROPIC_BASE_URL", "User")

if ($existingBaseUrl -eq "https://api.siliconflow.cn/" -and $existingKey) {
    Write-Host "✅ Detected existing configuration. Using saved API Key.｜检测到已有配置，将使用已保存的 API Key。" -ForegroundColor Green
    $apiKey = $existingKey
}

if (-not $apiKey) {
    Write-Host ""
    Write-Host "🔑 Please enter your SiliconCloud API Key｜设置你的 SiliconCloud API Key:" -ForegroundColor Cyan
    Write-Host "   You can get your API Key from｜可访问右边地址获取 API Key: https://cloud.siliconflow.cn/account/ak" -ForegroundColor Yellow
    Write-Host "   Note: The input is hidden for security.｜注意：输入的内容不会显示在屏幕上" -ForegroundColor Yellow
    Write-Host ""
    
    $secureKey = Read-Host -AsSecureString
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKey)
    $apiKey = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
    
    if (-not $apiKey) {
        Write-Host "⚠️  API Key cannot be empty. Please run the script again.｜API Key 未正确设置，请重新运行脚本" -ForegroundColor Red
        exit 1
    }
}

# --- Model Selection ---
Write-Host ""
Write-Host "🤖 Please select a model to use｜请选择需要使用的模型:" -ForegroundColor Cyan

$modelOptions = @(
    "moonshotai/Kimi-K2-Thinking",
    "moonshotai/Kimi-K2-Thinking-Turbo",
    "zai-org/GLM-4.6",
    "Pro/deepseek-ai/DeepSeek-V3.1-Terminus",
    "deepseek-ai/DeepSeek-V3.1-Terminus",
    "Pro/moonshotai/Kimi-K2-Instruct-0905",
    "moonshotai/Kimi-K2-Instruct-0905",
    "Qwen/Qwen3-Coder-480B-A35B-Instruct",
    "Qwen/Qwen3-Coder-30B-A3B-Instruct",
    "Custom (enter your own model)｜自定义 (手动输入模型)"
)

$selection = Show-Menu -Options $modelOptions -CurrentSelection 0

if ($selection -eq ($modelOptions.Count - 1)) {
    Write-Host ""
    Write-Host "✍️ Please enter the custom model name｜请输入自定义模型名称:" -ForegroundColor Cyan
    $customModel = Read-Host
    
    if (-not $customModel) {
        Write-Host "⚠️  Model name cannot be empty. Exiting.｜模型名称不能为空，脚本退出。" -ForegroundColor Red
        exit 1
    }
    $selectedModel = $customModel
} else {
    $selectedModel = $modelOptions[$selection]
}

Write-Host ""
Write-Host "✅ You have selected｜已选择模型: $selectedModel" -ForegroundColor Green

# --- Set Environment Variables ---
Write-Host ""
Write-Host "📝 Setting environment variables...｜正在设置环境变量..." -ForegroundColor Cyan

[System.Environment]::SetEnvironmentVariable("ANTHROPIC_BASE_URL", "https://api.siliconflow.cn/", "User")
[System.Environment]::SetEnvironmentVariable("ANTHROPIC_API_KEY", $apiKey, "User")
[System.Environment]::SetEnvironmentVariable("ANTHROPIC_MODEL", $selectedModel, "User")

# Update current session
$env:ANTHROPIC_BASE_URL = "https://api.siliconflow.cn/"
$env:ANTHROPIC_API_KEY = $apiKey
$env:ANTHROPIC_MODEL = $selectedModel

Write-Host "✅ Environment variables successfully set.｜环境变量设置成功。" -ForegroundColor Green

Write-Host ""
Write-Host "🎉 Configuration completed successfully｜配置已完成 🎉" -ForegroundColor Green
Write-Host ""
Write-Host "🚀 You can now start using Claude Code with｜使用下面命令进入 Claude Code:" -ForegroundColor Cyan
Write-Host "   claude" -ForegroundColor Yellow
Write-Host ""
Write-Host "💡 Note: Environment variables are set for your user account.｜注意：环境变量已为您的用户账户设置。" -ForegroundColor Yellow
Write-Host "💡 Restart PowerShell or open a new terminal to use Claude Code.｜重启 PowerShell 或打开新终端即可使用 Claude Code。" -ForegroundColor Yellow
Write-Host ""
