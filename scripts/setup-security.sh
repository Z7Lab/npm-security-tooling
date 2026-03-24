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

# Spinner for long-running commands (single-line progress indicator)
# Usage: run_with_spinner "Installing package..." npm install -g package
run_with_spinner() {
    local msg="$1"
    shift
    local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local delay=0.1
    local logfile=$(mktemp)

    # Run command in background, capture output
    "$@" > "$logfile" 2>&1 &
    local pid=$!

    # Show spinner while command runs
    local i=0
    while kill -0 "$pid" 2>/dev/null; do
        local char="${spinstr:$i:1}"
        printf "\r  %s %s" "$char" "$msg"
        i=$(( (i + 1) % ${#spinstr} ))
        sleep "$delay"
    done

    # Get exit code
    wait "$pid"
    local exit_code=$?

    # Clear spinner line
    printf "\r\033[K"

    # Show output if failed
    if [ $exit_code -ne 0 ]; then
        cat "$logfile"
    fi

    rm -f "$logfile"
    return $exit_code
}

# Check if Aikido Safe Chain is installed
echo -e "${BLUE}Checking Aikido Safe Chain installation...${NC}"
if command -v safe-chain &> /dev/null; then
    echo -e "${GREEN}✅ Aikido Safe Chain is already installed${NC}"
    safe-chain --version
else
    echo -e "${YELLOW}⚠️  Aikido Safe Chain not found${NC}"
    echo ""
    if run_with_spinner "Installing Aikido Safe Chain globally..." npm install -g @aikidosec/safe-chain; then
        echo -e "${GREEN}✅ Aikido Safe Chain installed${NC}"
    else
        echo -e "${YELLOW}⚠️  Aikido Safe Chain installation failed${NC}"
        exit 1
    fi
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

# Helper: add dual-scan wrapper to a shell rc file
add_dual_scan_wrapper() {
    local rc_file="$1"
    if [ ! -f "$rc_file" ]; then
        return
    fi
    # Remove old-style alias if present
    remove_socket_alias "$rc_file"
    local wrapper_path
    wrapper_path="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/npm-dual-scan.sh"
    if ! grep -q "npm-dual-scan.sh" "$rc_file"; then
        echo "" >> "$rc_file"
        echo "source $wrapper_path # Dual-scan: Socket + Aikido" >> "$rc_file"
        echo -e "${GREEN}✅ Dual-scan wrapper added to $rc_file${NC}"
    else
        echo -e "${GREEN}✅ Dual-scan wrapper already exists in $rc_file${NC}"
    fi
}

# Helper: remove Socket alias from a shell rc file (legacy cleanup)
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
        echo -e "${GREEN}✅ Legacy Socket alias removed from $rc_file${NC}"
    fi
}

# Helper: remove dual-scan wrapper from a shell rc file
remove_dual_scan_wrapper() {
    local rc_file="$1"
    if [ ! -f "$rc_file" ]; then
        return
    fi
    if grep -q "npm-dual-scan.sh" "$rc_file"; then
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' '/npm-dual-scan.sh/d' "$rc_file"
        else
            sed -i '/npm-dual-scan.sh/d' "$rc_file"
        fi
        echo -e "${GREEN}✅ Dual-scan wrapper removed from $rc_file${NC}"
    fi
    # Also clean up legacy alias
    remove_socket_alias "$rc_file"
}

# Check if Socket Firewall is installed
if command -v sfw &> /dev/null; then
    echo -e "${GREEN}✅ Socket Firewall (sfw) is installed${NC}"
    sfw --version
    echo ""
    echo "Socket + Aikido dual-scan mode:"
    echo "  Install commands (install/ci/add) go through BOTH scanners:"
    echo "    1. Socket dry-run scan (Socket.dev threat intelligence)"
    echo "    2. Aikido real install (Aikido threat intelligence)"
    echo "  Other commands (audit, view, etc.) go through Socket."
    echo ""
    echo "Options:"
    echo "  1) Enable dual-scan (both Socket + Aikido for installs)"
    echo "  2) Remove Socket (Aikido scans ALL package managers alone)"
    echo ""
    echo "Enable dual-scan for npm? (Y/n)"
    read -r keep_socket

    if [[ "$keep_socket" == "y" || "$keep_socket" == "Y" || "$keep_socket" == "" ]]; then
        cp ~/.bashrc ~/.bashrc.backup-$timestamp 2>/dev/null || true
        add_dual_scan_wrapper ~/.bashrc
        add_dual_scan_wrapper ~/.zshrc

        echo ""
        echo -e "${GREEN}✅ Dual-scan mode enabled:${NC}"
        echo "   - npm install/ci/add: Socket dry-run + Aikido install"
        echo "   - npm audit/view/etc: Socket passthrough"
        echo "   - npx/pnpm/yarn/bun: Aikido Safe Chain"
    else
        remove_dual_scan_wrapper ~/.bashrc
        remove_dual_scan_wrapper ~/.zshrc
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
        if run_with_spinner "Installing Socket Firewall..." npm install -g sfw && command -v sfw &> /dev/null; then
            echo -e "${GREEN}✅ Socket Firewall installed${NC}"
            sfw --version
            echo ""
            echo "Enabling dual-scan wrapper for npm..."
            cp ~/.bashrc ~/.bashrc.backup-$timestamp 2>/dev/null || true
            add_dual_scan_wrapper ~/.bashrc
            add_dual_scan_wrapper ~/.zshrc

            echo ""
            echo -e "${GREEN}✅ Dual-scan mode enabled:${NC}"
            echo "   - npm install/ci/add: Socket dry-run + Aikido install"
            echo "   - npm audit/view/etc: Socket passthrough"
            echo "   - npx/pnpm/yarn/bun: Aikido Safe Chain"
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
echo "🔍 npx-audit (CVE Scanner for Package Executors)"
echo "=========================================="
echo ""

# Find the npx-audit script — check common locations
NPX_AUDIT_SRC=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/npx-audit" ]; then
    NPX_AUDIT_SRC="$SCRIPT_DIR/npx-audit"
elif [ -f "./scripts/npx-audit" ]; then
    NPX_AUDIT_SRC="$(cd ./scripts && pwd)/npx-audit"
fi

if [ -n "$NPX_AUDIT_SRC" ]; then
    # Install to ~/.local/bin
    mkdir -p ~/.local/bin
    cp "$NPX_AUDIT_SRC" ~/.local/bin/npx-audit
    chmod +x ~/.local/bin/npx-audit

    # Ensure ~/.local/bin is in PATH
    if ! echo "$PATH" | grep -q "$HOME/.local/bin"; then
        for rc_file in ~/.bashrc ~/.zshrc; do
            if [ -f "$rc_file" ] && ! grep -q '.local/bin' "$rc_file"; then
                echo '' >> "$rc_file"
                echo '# Added by npm-security-tooling setup' >> "$rc_file"
                echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$rc_file"
            fi
        done
        export PATH="$HOME/.local/bin:$PATH"
    fi

    echo -e "${GREEN}✅ npx-audit installed to ~/.local/bin/npx-audit${NC}"

    # Initialize config + allowlist
    ~/.local/bin/npx-audit --init-config 2>/dev/null
    echo -e "${GREEN}✅ Config initialized (~/.config/npx-audit/)${NC}"

    # Generate shell wrapper init script
    NPX_AUDIT_INIT_DIR="$HOME/.config/npx-audit"
    mkdir -p "$NPX_AUDIT_INIT_DIR"
    cat > "$NPX_AUDIT_INIT_DIR/init.sh" << 'INITEOF'
# npx-audit shell integration
# Wraps npx, pnpm dlx, yarn dlx, bunx with CVE scanning
# Sourced AFTER Aikido safe-chain init so these functions take precedence

npx() {
    if command -v npx-audit > /dev/null 2>&1; then
        npx-audit exec --runner=npx "$@"
    elif type aikido-npx > /dev/null 2>&1; then
        aikido-npx "$@"
    else
        command npx "$@"
    fi
}

# Override pnpm only for 'pnpm dlx' — pass everything else through
pnpm() {
    if [ "$1" = "dlx" ] && command -v npx-audit > /dev/null 2>&1; then
        shift
        npx-audit exec --runner=pnpm-dlx "$@"
    elif type aikido-pnpm > /dev/null 2>&1; then
        aikido-pnpm "$@"
    else
        command pnpm "$@"
    fi
}

# Override yarn only for 'yarn dlx' — pass everything else through
yarn() {
    if [ "$1" = "dlx" ] && command -v npx-audit > /dev/null 2>&1; then
        shift
        npx-audit exec --runner=yarn-dlx "$@"
    elif type aikido-yarn > /dev/null 2>&1; then
        aikido-yarn "$@"
    else
        command yarn "$@"
    fi
}

bunx() {
    if command -v npx-audit > /dev/null 2>&1; then
        npx-audit exec --runner=bunx "$@"
    elif type aikido-bunx > /dev/null 2>&1; then
        aikido-bunx "$@"
    else
        command bunx "$@"
    fi
}
INITEOF

    echo -e "${GREEN}✅ Shell wrappers created (~/.config/npx-audit/init.sh)${NC}"

    # Source init.sh in shell rc files (AFTER Aikido's init)
    for rc_file in ~/.bashrc ~/.zshrc; do
        if [ -f "$rc_file" ] && ! grep -q 'npx-audit/init.sh' "$rc_file"; then
            echo '' >> "$rc_file"
            echo '# npx-audit: CVE scanning for npx, pnpm dlx, yarn dlx, bunx' >> "$rc_file"
            echo '[ -f ~/.config/npx-audit/init.sh ] && source ~/.config/npx-audit/init.sh' >> "$rc_file"
            echo -e "${GREEN}✅ Shell integration added to $(basename $rc_file)${NC}"
        else
            [ -f "$rc_file" ] && echo -e "${GREEN}✅ Shell integration already in $(basename $rc_file)${NC}"
        fi
    done
else
    echo -e "${YELLOW}⚠️  npx-audit script not found — skipping CVE scanner setup${NC}"
    echo "   Install manually: copy scripts/npx-audit to ~/.local/bin/"
fi

echo ""
echo "=========================================="
echo "🔬 SAST Scanning Tools (Static Analysis)"
echo "=========================================="
echo ""
echo "Static analysis tools detect security vulnerabilities in your source code"
echo "(eval(), innerHTML, SQL injection patterns, obfuscated code, etc.)"
echo ""
echo "Four tools available:"
echo "  1. ESLint + security plugins  — Pattern-based JS/TS vulnerability detection"
echo "  2. Semgrep                    — Multi-language SAST with curated security rules"
echo "  3. js-x-ray                   — Detects obfuscated code and malicious patterns"
echo "  4. TypeScript threat scanner  — Build config, @types, and compiler plugin risks"
echo ""
echo "Install SAST scanning tools? (y/N)"
read -r install_sast

if [[ "$install_sast" == "y" || "$install_sast" == "Y" ]]; then

    # ESLint + security plugins
    echo ""
    echo -e "${BLUE}Installing ESLint security plugins...${NC}"
    if command -v eslint &> /dev/null; then
        echo -e "${GREEN}   ✅ ESLint already installed ($(eslint --version))${NC}"
    else
        if run_with_spinner "   Installing ESLint..." npm install -g eslint && command -v eslint &> /dev/null; then
            echo -e "${GREEN}   ✅ ESLint installed ($(eslint --version))${NC}"
        else
            echo -e "${YELLOW}   ⚠️  ESLint installation failed${NC}"
        fi
    fi

    if run_with_spinner "   Installing ESLint security plugins..." npm install -g eslint-plugin-security eslint-plugin-no-unsanitized; then
        echo -e "${GREEN}   ✅ ESLint security plugins installed${NC}"
    else
        echo -e "${YELLOW}   ⚠️  ESLint security plugins installation failed${NC}"
    fi

    # Semgrep
    echo ""
    echo -e "${BLUE}Installing Semgrep...${NC}"
    if command -v semgrep &> /dev/null; then
        echo -e "${GREEN}   ✅ Semgrep already installed ($(semgrep --version 2>&1))${NC}"
    else
        if command -v pip3 &> /dev/null; then
            if run_with_spinner "   Installing Semgrep via pip3..." pip3 install semgrep && command -v semgrep &> /dev/null; then
                echo -e "${GREEN}   ✅ Semgrep installed ($(semgrep --version 2>&1))${NC}"
            else
                echo -e "${YELLOW}   ⚠️  Semgrep installation failed — install manually later${NC}"
            fi
        elif command -v brew &> /dev/null; then
            if run_with_spinner "   Installing Semgrep via brew..." brew install semgrep && command -v semgrep &> /dev/null; then
                echo -e "${GREEN}   ✅ Semgrep installed ($(semgrep --version 2>&1))${NC}"
            else
                echo -e "${YELLOW}   ⚠️  Semgrep installation failed — install manually later${NC}"
            fi
        else
            echo -e "${YELLOW}   ⚠️  Cannot install Semgrep: pip3 or brew required${NC}"
            echo "      Install manually: pip3 install semgrep OR brew install semgrep"
        fi
    fi

    # js-x-ray
    echo ""
    echo -e "${BLUE}Installing js-x-ray...${NC}"
    if run_with_spinner "   Installing js-x-ray..." npm install -g @nodesecure/js-x-ray && node -e "require('@nodesecure/js-x-ray')" 2>/dev/null; then
        echo -e "${GREEN}   ✅ @nodesecure/js-x-ray installed${NC}"
    else
        echo -e "${YELLOW}   ⚠️  js-x-ray installation failed${NC}"
    fi

    echo ""
    echo -e "${GREEN}✅ SAST tools setup complete${NC}"
    echo ""
    echo -e "${GREEN}TypeScript threat scanner included (no additional install needed)${NC}"
    echo "   Run: ./scripts/scan-ts-threats.sh /path/to/project"
    echo "   Run: node ./scripts/check-npm-metadata.mjs --dir /path/to/project"
    echo ""
    echo "   Or run all SAST tools together:"
    echo "   Run: ./scripts/sast-scan.sh /path/to/project"
else
    echo -e "${BLUE}ℹ️  Skipping SAST tools${NC}"
    echo "   You can install them later by re-running this script"
fi

echo ""
echo "=========================================="
echo "✅ Setup Complete!"
echo "=========================================="
echo ""
echo "Protection Summary:"
echo "  🛡️  Aikido Safe Chain: Shell wrappers for npm, npx, pnpm, pnpx, yarn, bun, bunx"
echo "  🔍 npx-audit: CVE scanning for npx, pnpm dlx, yarn dlx, bunx"
echo "  🔒 ignore-scripts: Disabled for all package managers"
echo "  📌 save-exact: Enabled for npm, pnpm, yarn, bun"
echo "  ⏱️  minimum-release-age: 24h delay for pnpm, yarn, bun"
echo "  ✍️  provenance: Enabled for npm (cryptographic verification)"
echo ""

if command -v sfw &> /dev/null && grep -q "npm-dual-scan.sh" ~/.bashrc 2>/dev/null; then
    echo "  🔐 Socket + Aikido dual-scan: npm installs scanned by both"
elif command -v sfw &> /dev/null && grep -q "alias npm='sfw npm'" ~/.bashrc 2>/dev/null; then
    echo "  🔐 Socket Firewall: npm alias (legacy, consider re-running setup)"
fi

if command -v eslint &> /dev/null && npm list -g eslint-plugin-security &>/dev/null 2>&1; then
    echo "  🔬 SAST: ESLint security plugins"
fi
if command -v semgrep &> /dev/null; then
    echo "  🔬 SAST: Semgrep"
fi
if node -e "require('@nodesecure/js-x-ray')" 2>/dev/null; then
    echo "  🔬 SAST: js-x-ray"
fi

if [ -f "$SCRIPT_DIR/scan-ts-threats.sh" ]; then
    echo "  🔬 SAST: TypeScript threat scanner (build configs, @types, compiler plugins)"
fi
if [ -f "$SCRIPT_DIR/check-npm-metadata.mjs" ]; then
    echo "  🔬 Supply chain: npm metadata checker (typosquatting, recent publishes)"
fi

echo ""
echo "Next steps:"
echo "  1. Open a new terminal (or run: source ~/.bashrc)"
echo "  2. Verify protection is active:"
echo "     ./scripts/verify-security.sh"
echo ""
echo "  3. Test installations:"
echo "     npm install <package>    # Protected by Aikido (or Socket if alias active)"
echo "     npx <package>            # Protected by npx-audit (CVE) + Aikido (malware)"
echo "     pnpm install <package>   # Protected by Aikido"
echo "     pnpm dlx <package>       # Protected by npx-audit (CVE) + Aikido (malware)"
echo "     yarn add <package>       # Protected by Aikido"
echo "     bun add <package>        # Protected by Aikido"
echo ""
echo "  4. Run security audit across all projects:"
echo "     ./scripts/audit-all-projects.sh ~/dev/projects"
echo "     (or specify any directory to scan)"
echo ""
echo "  5. Run SAST scan on your source code:"
echo "     ./scripts/sast-scan.sh ~/dev/projects"
echo ""
echo "  6. Check npm supply chain metadata:"
echo "     node ./scripts/check-npm-metadata.mjs --dir ~/dev/projects/my-app"
echo ""
echo "  7. Scan for TypeScript/build tooling threats:"
echo "     ./scripts/scan-ts-threats.sh ~/dev/projects/my-app"
echo ""
echo "⚠️  Important: Aikido scans for MALWARE (backdoors, data exfiltration)."
echo "   npx-audit scans for known CVE VULNERABILITIES in package dependency trees."
echo "   For CVE coverage of installed project dependencies, use audit-all-projects.sh."
echo ""
echo "⚠️  Note: Some packages your projects depend on may require lifecycle"
echo "   scripts to build properly. If a project installation fails, you can"
echo "   override per-project by creating .npmrc or .pnpmrc with:"
echo "   ignore-scripts=false"
echo ""
