#!/bin/bash
# Comprehensive npm/pnpm/yarn/bun security setup
# Installs Aikido Safe Chain and hardens all package managers
#
# Usage: ./setup-security.sh
# (No arguments needed - configures your home directory)

set -e

# Ignore any arguments (common mistake - audit script takes directory, this doesn't)
if [ -n "$1" ]; then
    echo "ℹ️  Note: This script configures your system globally (no arguments needed)"
    echo ""
fi

echo "=========================================="
echo "📦 Package Manager Security Setup"
echo "=========================================="
echo ""

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if Aikido Safe Chain is installed
echo -e "${BLUE}Checking Aikido Safe Chain installation...${NC}"
if command -v safe-chain &> /dev/null; then
    echo -e "${GREEN}✅ Aikido Safe Chain is already installed${NC}"
    safe-chain --version
else
    echo -e "${YELLOW}⚠️  Aikido Safe Chain not found${NC}"
    echo ""
    echo "Installing Aikido Safe Chain globally..."
    npm install -g @aikidosec/safe-chain
    echo -e "${GREEN}✅ Aikido Safe Chain installed${NC}"
fi

# Run safe-chain setup to create shell wrapper functions (npm, npx, pnpm, yarn, bun, etc.)
# This is the critical step that actually enables interception — without it, package manager
# commands bypass Aikido entirely.
echo ""
echo -e "${BLUE}Configuring Aikido shell integration...${NC}"
if [ -f ~/.safe-chain/scripts/init-posix.sh ]; then
    echo -e "${GREEN}✅ Aikido shell integration already configured${NC}"
else
    safe-chain setup
    if [ -f ~/.safe-chain/scripts/init-posix.sh ]; then
        echo -e "${GREEN}✅ Aikido shell integration configured${NC}"
    else
        echo -e "${YELLOW}⚠️  safe-chain setup did not create shell integration${NC}"
        echo "   Try running 'safe-chain setup' manually after this script completes"
    fi
fi

echo ""
echo "=========================================="
echo "🔧 Configuring Package Managers"
echo "=========================================="
echo ""

# Backup existing configs
timestamp=$(date +%Y%m%d-%H%M%S)

# 1. NPM Configuration
echo -e "${BLUE}[1/4] Configuring npm (~/.npmrc)...${NC}"
if [ -f ~/.npmrc ]; then
    cp ~/.npmrc ~/.npmrc.backup-$timestamp
    echo "   Backup created: ~/.npmrc.backup-$timestamp"
fi

# Check and add npm settings
npm_config_updated=false

if ! grep -q "ignore-scripts=true" ~/.npmrc 2>/dev/null; then
    npm config set ignore-scripts true
    npm_config_updated=true
fi

if ! grep -q "save-exact=true" ~/.npmrc 2>/dev/null; then
    npm config set save-exact true
    npm_config_updated=true
fi

if ! grep -q "save-prefix=''" ~/.npmrc 2>/dev/null && ! grep -q 'save-prefix=""' ~/.npmrc 2>/dev/null; then
    npm config set save-prefix ''
    npm_config_updated=true
fi

if ! grep -q "provenance=true" ~/.npmrc 2>/dev/null; then
    npm config set provenance true
    npm_config_updated=true
fi

if [ "$npm_config_updated" = true ]; then
    echo -e "${GREEN}   ✅ npm configured${NC}"
else
    echo -e "${GREEN}   ✅ npm already configured${NC}"
fi

# 2. PNPM Configuration
echo ""
echo -e "${BLUE}[2/5] Configuring pnpm (~/.pnpmrc)...${NC}"

if ! command -v pnpm &> /dev/null; then
    echo -e "${YELLOW}   ⚠️  pnpm not installed - skipping${NC}"
else
    if [ -f ~/.pnpmrc ]; then
        cp ~/.pnpmrc ~/.pnpmrc.backup-$timestamp
        echo "   Backup created: ~/.pnpmrc.backup-$timestamp"
    fi

    pnpm_config_updated=false
    touch ~/.pnpmrc

if ! grep -q "^ignore-scripts=true" ~/.pnpmrc; then
    echo "ignore-scripts=true" >> ~/.pnpmrc
    pnpm_config_updated=true
fi

if ! grep -q "^save-exact=true" ~/.pnpmrc; then
    echo "save-exact=true" >> ~/.pnpmrc
    pnpm_config_updated=true
fi

# Add minimum release age (24 hours = 1440 minutes)
if ! grep -q "^minimum-release-age=" ~/.pnpmrc; then
    echo "minimum-release-age=1440" >> ~/.pnpmrc
    pnpm_config_updated=true
fi

    if [ "$pnpm_config_updated" = true ]; then
        echo -e "${GREEN}   ✅ pnpm configured (with 24h minimum release age)${NC}"
    else
        echo -e "${GREEN}   ✅ pnpm already configured${NC}"
    fi
fi

# 3. BUN Configuration
echo ""
echo -e "${BLUE}[3/5] Configuring bun (bunfig.toml)...${NC}"

if ! command -v bun &> /dev/null; then
    echo -e "${YELLOW}   ⚠️  bun not installed - skipping${NC}"
else
    if [ -f ~/bunfig.toml ]; then
        cp ~/bunfig.toml ~/bunfig.toml.backup-$timestamp
        echo "   Backup created: ~/bunfig.toml.backup-$timestamp"
    fi

    bun_config_updated=false
    touch ~/bunfig.toml

# Check if [install] section exists
if ! grep -q "^\[install\]" ~/bunfig.toml; then
    echo "" >> ~/bunfig.toml
    echo "[install]" >> ~/bunfig.toml
    bun_config_updated=true
fi

# Add exact version pinning
if ! grep -q "^exact = true" ~/bunfig.toml; then
    # Insert after [install] section
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' '/^\[install\]/a\
exact = true' ~/bunfig.toml
    else
        sed -i '/^\[install\]/a exact = true' ~/bunfig.toml
    fi
    bun_config_updated=true
fi

# Add minimum release age (24 hours = 86400 seconds)
if ! grep -q "^minimumReleaseAge = " ~/bunfig.toml; then
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' '/^\[install\]/a\
minimumReleaseAge = 86400' ~/bunfig.toml
    else
        sed -i '/^\[install\]/a minimumReleaseAge = 86400' ~/bunfig.toml
    fi
    bun_config_updated=true
fi

    if [ "$bun_config_updated" = true ]; then
        echo -e "${GREEN}   ✅ bun configured (with 24h minimum release age)${NC}"
    else
        echo -e "${GREEN}   ✅ bun already configured${NC}"
    fi
fi

# 4. YARN Configuration (Yarn 1.x classic)
echo ""
echo -e "${BLUE}[4/5] Configuring yarn (~/.yarnrc)...${NC}"

if ! command -v yarn &> /dev/null; then
    echo -e "${YELLOW}   ⚠️  yarn not installed - skipping${NC}"
else
    if [ -f ~/.yarnrc ]; then
        cp ~/.yarnrc ~/.yarnrc.backup-$timestamp
        echo "   Backup created: ~/.yarnrc.backup-$timestamp"
    fi

    yarn_config_updated=false
    touch ~/.yarnrc

if ! grep -q "^--ignore-scripts true" ~/.yarnrc; then
    echo "--ignore-scripts true" >> ~/.yarnrc
    yarn_config_updated=true
fi

if ! grep -q "^save-exact true" ~/.yarnrc; then
    echo "save-exact true" >> ~/.yarnrc
    yarn_config_updated=true
fi

    if [ "$yarn_config_updated" = true ]; then
        echo -e "${GREEN}   ✅ yarn (classic) configured${NC}"
    else
        echo -e "${GREEN}   ✅ yarn (classic) already configured${NC}"
    fi

    # 5. YARN Modern (v2+) Configuration
    echo ""
    echo -e "${BLUE}[5/5] Configuring yarn modern (~/.yarnrc.yml)...${NC}"
    if [ -f ~/.yarnrc.yml ]; then
        cp ~/.yarnrc.yml ~/.yarnrc.yml.backup-$timestamp
        echo "   Backup created: ~/.yarnrc.yml.backup-$timestamp"

    yarn_modern_updated=false
    if ! grep -q "enableScripts: false" ~/.yarnrc.yml; then
        echo "enableScripts: false" >> ~/.yarnrc.yml
        yarn_modern_updated=true
    fi

    # Add minimum release age (24 hours = 1440 minutes)
    if ! grep -q "npmMinimalAgeGate:" ~/.yarnrc.yml; then
        echo "npmMinimalAgeGate: 1440" >> ~/.yarnrc.yml
        yarn_modern_updated=true
    fi

    if [ "$yarn_modern_updated" = true ]; then
        echo -e "${GREEN}   ✅ yarn modern configured (with 24h minimum release age)${NC}"
    else
        echo -e "${GREEN}   ✅ yarn modern already configured${NC}"
    fi
    else
        cat > ~/.yarnrc.yml << EOF
enableScripts: false
npmMinimalAgeGate: 1440
EOF
        echo -e "${GREEN}   ✅ yarn modern configured (with 24h minimum release age)${NC}"
    fi
fi

echo ""
echo "=========================================="
echo "🛡️  Optional: Socket Firewall (npm only)"
echo "=========================================="
echo ""
echo "Aikido Safe Chain now protects ALL package managers."
echo "Socket Firewall can be added for enhanced npm-specific scanning."
echo ""

# Helper: add Socket alias to a shell rc file, removing any stale alias first
add_socket_alias() {
    local rc_file="$1"
    if [ ! -f "$rc_file" ]; then
        return
    fi
    if ! grep -q "alias npm='sfw npm'" "$rc_file"; then
        echo "" >> "$rc_file"
        echo "# NPM Security - Socket Firewall (additional layer, runs AFTER Aikido)" >> "$rc_file"
        echo "# NOTE: This alias overrides Aikido's npm() shell function for npm only." >> "$rc_file"
        echo "# Other commands (npx, pnpm, yarn, bun) remain protected by Aikido." >> "$rc_file"
        echo "alias npm='sfw npm'" >> "$rc_file"
        echo -e "${GREEN}✅ Socket Firewall alias added to $rc_file${NC}"
    else
        echo -e "${GREEN}✅ Socket Firewall alias already exists in $rc_file${NC}"
    fi
}

# Helper: remove Socket alias from a shell rc file
remove_socket_alias() {
    local rc_file="$1"
    if [ ! -f "$rc_file" ]; then
        return
    fi
    if grep -q "alias npm='sfw npm'" "$rc_file"; then
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' "/alias npm='sfw npm'/d" "$rc_file"
            sed -i '' '/# NPM Security - Socket Firewall/d' "$rc_file"
            sed -i '' '/# NOTE: This alias overrides/d' "$rc_file"
            sed -i '' '/# Other commands (npx, pnpm, yarn, bun)/d' "$rc_file"
        else
            sed -i "/alias npm='sfw npm'/d" "$rc_file"
            sed -i '/# NPM Security - Socket Firewall/d' "$rc_file"
            sed -i '/# NOTE: This alias overrides/d' "$rc_file"
            sed -i '/# Other commands (npx, pnpm, yarn, bun)/d' "$rc_file"
        fi
        echo -e "${GREEN}✅ Socket Firewall alias removed from $rc_file${NC}"
    fi
}

# Check if Socket Firewall is installed
if command -v sfw &> /dev/null; then
    echo -e "${GREEN}✅ Socket Firewall (sfw) is installed${NC}"
    sfw --version
    echo ""
    echo -e "${YELLOW}NOTE:${NC} Socket's 'alias npm=sfw npm' overrides Aikido's npm() wrapper."
    echo "  This means npm goes through Socket only (not Aikido) for malware scanning."
    echo "  All other commands (npx, pnpm, yarn, bun) still go through Aikido."
    echo ""
    echo "Options:"
    echo "  1) Keep Socket alias for npm (Socket scans npm, Aikido scans everything else)"
    echo "  2) Remove Socket alias (Aikido scans ALL package managers uniformly)"
    echo ""
    echo "Keep Socket Firewall alias for npm? (Y/n)"
    read -r keep_socket

    if [[ "$keep_socket" == "y" || "$keep_socket" == "Y" || "$keep_socket" == "" ]]; then
        cp ~/.bashrc ~/.bashrc.backup-$timestamp 2>/dev/null || true
        add_socket_alias ~/.bashrc
        add_socket_alias ~/.zshrc

        echo ""
        echo -e "${YELLOW}⚠️  Split protection mode:${NC}"
        echo "   - npm: Socket Firewall scans (alias overrides Aikido)"
        echo "   - npx/pnpm/yarn/bun: Aikido Safe Chain scans"
    else
        remove_socket_alias ~/.bashrc
        remove_socket_alias ~/.zshrc
        echo ""
        echo -e "${GREEN}✅ Aikido now protects ALL package managers uniformly (including npm)${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  Socket Firewall not installed${NC}"
    echo ""
    echo "Socket Firewall adds an extra layer of npm-specific threat intelligence."
    echo "Do you want to install Socket Firewall? (y/N)"
    read -r install_socket

    if [[ "$install_socket" == "y" || "$install_socket" == "Y" ]]; then
        echo ""
        echo "Installing Socket Firewall..."
        npm install -g sfw

        if command -v sfw &> /dev/null; then
            echo -e "${GREEN}✅ Socket Firewall installed${NC}"
            sfw --version
            echo ""
            echo "Adding Socket Firewall alias for npm..."
            cp ~/.bashrc ~/.bashrc.backup-$timestamp 2>/dev/null || true
            add_socket_alias ~/.bashrc
            add_socket_alias ~/.zshrc

            echo ""
            echo -e "${YELLOW}⚠️  Split protection mode:${NC}"
            echo "   - npm: Socket Firewall scans (alias overrides Aikido)"
            echo "   - npx/pnpm/yarn/bun: Aikido Safe Chain scans"
        else
            echo -e "${YELLOW}⚠️  Socket Firewall installation failed${NC}"
            echo "   Continuing with Aikido-only protection"
        fi
    else
        echo -e "${BLUE}ℹ️  Skipping Socket Firewall${NC}"
        echo "   All package managers protected by Aikido only"
    fi
fi

echo ""
echo "=========================================="
echo "✅ Setup Complete!"
echo "=========================================="
echo ""
echo "Protection Summary:"
echo "  🛡️  Aikido Safe Chain: Shell wrappers for npm, npx, pnpm, pnpx, yarn, bun, bunx"
echo "  🔒 ignore-scripts: Disabled for all package managers"
echo "  📌 save-exact: Enabled for npm, pnpm, yarn, bun"
echo "  ⏱️  minimum-release-age: 24h delay for pnpm, yarn, bun"
echo "  ✍️  provenance: Enabled for npm (cryptographic verification)"
echo ""

if command -v sfw &> /dev/null && grep -q "alias npm='sfw npm'" ~/.bashrc 2>/dev/null; then
    echo "  🔐 Socket Firewall: npm alias (overrides Aikido for npm only)"
    echo ""
fi

echo "Next steps:"
echo "  1. Open a new terminal (or run: source ~/.bashrc)"
echo "  2. Verify protection is active:"
echo "     ./scripts/verify-security.sh"
echo ""
echo "  3. Test installations:"
echo "     npm install <package>    # Protected by Aikido (or Socket if alias active)"
echo "     npx <package>            # Protected by Aikido (malware scanning)"
echo "     pnpm install <package>   # Protected by Aikido"
echo "     yarn add <package>       # Protected by Aikido"
echo "     bun add <package>        # Protected by Aikido"
echo ""
echo "  4. Run security audit across all projects:"
echo "     ./scripts/audit-all-projects.sh ~/dev/projects"
echo "     (or specify any directory to scan)"
echo ""
echo "⚠️  Important: Aikido scans for MALWARE (backdoors, data exfiltration)."
echo "   It does NOT scan for known CVE vulnerabilities (like npm audit does)."
echo "   For CVE coverage of installed dependencies, use audit-all-projects.sh."
echo "   npx-invoked packages are NOT covered by npm audit — only by Aikido's malware scan."
echo ""
echo "⚠️  Note: Some packages your projects depend on may require lifecycle"
echo "   scripts to build properly. If a project installation fails, you can"
echo "   override per-project by creating .npmrc or .pnpmrc with:"
echo "   ignore-scripts=false"
echo ""
