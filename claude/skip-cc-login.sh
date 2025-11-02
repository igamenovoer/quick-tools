#!/bin/bash

# Script to skip Claude Code onboarding/login process
# 跳过 Claude Code 登录流程的脚本

set -e

echo "=== Claude Code Login Skip Script｜Claude Code 登录跳过脚本 ==="
echo ""

# --- Check Node.js ---
echo "🔍 Checking Node.js installation｜检查 Node.js 安装..."
if ! command -v node >/dev/null 2>&1; then
    echo "❌ Node.js not found｜未找到 Node.js"
    echo ""
    echo "📋 Please install Node.js first｜请先安装 Node.js:"
    echo "   • Linux/macOS: Install via nvm"
    echo "     curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash"
    echo "     source ~/.nvm/nvm.sh"
    echo "     nvm install 22"
    echo "   • Or download from: https://nodejs.org/"
    echo ""
    exit 1
fi

node_version=$(node -v)
echo "✅ Node.js found｜找到 Node.js: $node_version"

# --- Check npm ---
echo "🔍 Checking npm installation｜检查 npm 安装..."
if ! command -v npm >/dev/null 2>&1; then
    echo "❌ npm not found｜未找到 npm"
    echo ""
    echo "📋 npm should come with Node.js. Please reinstall Node.js."
    echo "   npm 应该随 Node.js 一起安装，请重新安装 Node.js"
    echo ""
    exit 1
fi

npm_version=$(npm -v)
echo "✅ npm found｜找到 npm: v$npm_version"

# --- Check Claude Code ---
echo "🔍 Checking Claude Code installation｜检查 Claude Code 安装..."
if ! command -v claude >/dev/null 2>&1; then
    echo "❌ Claude Code not found｜未找到 Claude Code"
    echo ""
    echo "📋 Please install Claude Code first｜请先安装 Claude Code:"
    echo "   npm install -g @anthropic-ai/claude-code"
    echo ""
    echo "   If you get permission errors｜如果遇到权限错误:"
    echo "   sudo npm install -g @anthropic-ai/claude-code"
    echo ""
    exit 1
fi

claude_version=$(claude --version 2>/dev/null || echo "unknown")
echo "✅ Claude Code found｜找到 Claude Code: $claude_version"

# --- Skip onboarding ---
echo ""
echo "🔧 Configuring Claude Code to skip onboarding｜配置 Claude Code 跳过登录..."

config_file="$HOME/.claude.json"

node --eval '
    const fs = require("fs");
    const os = require("os");
    const path = require("path");
    const homeDir = os.homedir(); 
    const filePath = path.join(homeDir, ".claude.json");
    
    try {
        let config = {};
        
        // Read existing config if it exists
        if (fs.existsSync(filePath)) {
            const content = fs.readFileSync(filePath, "utf-8");
            try {
                config = JSON.parse(content);
                console.log("📖 Found existing configuration｜找到现有配置");
            } catch (e) {
                console.log("⚠️  Existing config is invalid, creating new one｜现有配置无效，创建新配置");
            }
        } else {
            console.log("📝 Creating new configuration｜创建新配置");
        }
        
        // Set the flag
        config.hasCompletedOnboarding = true;
        
        // Write back
        fs.writeFileSync(filePath, JSON.stringify(config, null, 2), "utf-8");
        console.log("✅ Configuration updated successfully｜配置更新成功");
        console.log("📁 Config file location｜配置文件位置: " + filePath);
        
    } catch (e) {
        console.error("❌ Error updating configuration｜配置更新失败:", e.message);
        process.exit(1);
    }
'

if [ $? -eq 0 ]; then
    echo ""
    echo "🎉 Successfully configured Claude Code to skip onboarding!｜成功配置 Claude Code 跳过登录！"
    echo ""
    echo "✨ You can now use Claude Code directly with:｜现在可以直接使用 Claude Code:"
    echo "   claude"
    echo ""
else
    echo ""
    echo "❌ Failed to configure Claude Code｜配置失败"
    echo "Please check the error messages above｜请查看上面的错误信息"
    exit 1
fi
