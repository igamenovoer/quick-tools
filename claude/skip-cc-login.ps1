# Script to skip Claude Code onboarding/login process
# 跳过 Claude Code 登录流程的脚本

$ErrorActionPreference = "Stop"

Write-Host "=== Claude Code Login Skip Script｜Claude Code 登录跳过脚本 ===" -ForegroundColor Cyan
Write-Host ""

# --- Check Node.js ---
Write-Host "🔍 Checking Node.js installation｜检查 Node.js 安装..."
try {
    $nodeVersion = node --version 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Node.js found｜找到 Node.js: $nodeVersion" -ForegroundColor Green
    } else {
        throw "Node.js command failed"
    }
} catch {
    Write-Host "❌ Node.js not found｜未找到 Node.js" -ForegroundColor Red
    Write-Host ""
    Write-Host "📋 Please install Node.js first｜请先安装 Node.js:" -ForegroundColor Yellow
    Write-Host "   • Windows: Install via nvm-windows or official installer"
    Write-Host "     nvm-windows: https://github.com/coreybutler/nvm-windows"
    Write-Host "     Official: https://nodejs.org/"
    Write-Host ""
    Write-Host "   After installation, restart PowerShell and run this script again."
    Write-Host "   安装完成后，请重启 PowerShell 并重新运行此脚本。"
    Write-Host ""
    exit 1
}

# --- Check npm ---
Write-Host "🔍 Checking npm installation｜检查 npm 安装..."
try {
    $npmVersion = npm --version 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ npm found｜找到 npm: v$npmVersion" -ForegroundColor Green
    } else {
        throw "npm command failed"
    }
} catch {
    Write-Host "❌ npm not found｜未找到 npm" -ForegroundColor Red
    Write-Host ""
    Write-Host "📋 npm should come with Node.js. Please reinstall Node.js."
    Write-Host "   npm 应该随 Node.js 一起安装，请重新安装 Node.js"
    Write-Host ""
    exit 1
}

# --- Check Claude Code ---
Write-Host "🔍 Checking Claude Code installation｜检查 Claude Code 安装..."
try {
    $claudeCmd = Get-Command claude -ErrorAction SilentlyContinue
    if ($claudeCmd) {
        $claudeVersion = claude --version 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ Claude Code found｜找到 Claude Code: $claudeVersion" -ForegroundColor Green
        } else {
            $claudeVersion = "installed"
            Write-Host "✅ Claude Code found｜找到 Claude Code: $claudeVersion" -ForegroundColor Green
        }
    } else {
        throw "Claude Code not found"
    }
} catch {
    Write-Host "❌ Claude Code not found｜未找到 Claude Code" -ForegroundColor Red
    Write-Host ""
    Write-Host "📋 Please install Claude Code first｜请先安装 Claude Code:" -ForegroundColor Yellow
    Write-Host "   npm install -g @anthropic-ai/claude-code"
    Write-Host ""
    Write-Host "   If you get permission errors, run PowerShell as Administrator"
    Write-Host "   如果遇到权限错误，请以管理员身份运行 PowerShell"
    Write-Host ""
    exit 1
}

# --- Skip onboarding ---
Write-Host ""
Write-Host "🔧 Configuring Claude Code to skip onboarding｜配置 Claude Code 跳过登录..." -ForegroundColor Cyan

$configFile = Join-Path $env:USERPROFILE ".claude.json"

try {
    $config = @{}
    
    # Read existing config if it exists
    if (Test-Path $configFile) {
        try {
            $configContent = Get-Content $configFile -Raw -ErrorAction Stop
            $config = $configContent | ConvertFrom-Json -AsHashtable -ErrorAction Stop
            Write-Host "📖 Found existing configuration｜找到现有配置"
        } catch {
            Write-Host "⚠️  Existing config is invalid, creating new one｜现有配置无效，创建新配置" -ForegroundColor Yellow
            $config = @{}
        }
    } else {
        Write-Host "📝 Creating new configuration｜创建新配置"
    }
    
    # Set the flag
    $config.hasCompletedOnboarding = $true
    
    # Write back
    $config | ConvertTo-Json -Depth 10 | Set-Content $configFile -Encoding UTF8 -ErrorAction Stop
    
    Write-Host "✅ Configuration updated successfully｜配置更新成功" -ForegroundColor Green
    Write-Host "📁 Config file location｜配置文件位置: $configFile"
    
    Write-Host ""
    Write-Host "🎉 Successfully configured Claude Code to skip onboarding!｜成功配置 Claude Code 跳过登录！" -ForegroundColor Green
    Write-Host ""
    Write-Host "✨ You can now use Claude Code directly with:｜现在可以直接使用 Claude Code:"
    Write-Host "   claude" -ForegroundColor Cyan
    Write-Host ""
    
} catch {
    Write-Host ""
    Write-Host "❌ Failed to configure Claude Code｜配置失败" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)"
    Write-Host "Please check the error messages above｜请查看上面的错误信息"
    exit 1
}
