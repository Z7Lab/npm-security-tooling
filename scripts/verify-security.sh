#!/bin/bash
# Verify that npm security tooling is properly configured
# Run this anytime to confirm your protection is active
#
# Usage: ./verify-security.sh

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "=========================================="
echo "Security Verification Check"
echo "=========================================="
echo ""

pass_count=0
warn_count=0
fail_count=0

pass() {
    echo -e "  ${GREEN}PASS${NC}  $1"
    ((pass_count++))
}

warn() {
    echo -e "  ${YELLOW}WARN${NC}  $1"
    ((warn_count++))
}

fail() {
    echo -e "  ${RED}FAIL${NC}  $1"
    ((fail_count++))
}

# ── 1. Aikido Safe Chain Installation ──────────────────────────

echo -e "${BLUE}[1/7] Aikido Safe Chain${NC}"

if command -v safe-chain &> /dev/null; then
    version=$(safe-chain --version 2>&1)
    pass "safe-chain installed ($version)"
else
    fail "safe-chain not installed — run: npm install -g @aikidosec/safe-chain"
fi

if [ -f ~/.safe-chain/scripts/init-posix.sh ]; then
    pass "Shell integration file exists (~/.safe-chain/scripts/init-posix.sh)"
else
    fail "Shell integration missing — run: safe-chain setup"
fi

# Check if init script is sourced in shell rc files
shell_sourced=false
for rc_file in ~/.bashrc ~/.zshrc ~/.bash_profile ~/.profile; do
    if [ -f "$rc_file" ] && grep -q "safe-chain" "$rc_file" 2>/dev/null; then
        pass "Shell integration sourced in $(basename $rc_file)"
        shell_sourced=true
        break
    fi
done
if [ "$shell_sourced" = false ]; then
    fail "Shell integration not sourced in any rc file — run: safe-chain setup"
fi

echo ""

# ── 2. Package Manager Interception ───────────────────────────

echo -e "${BLUE}[2/7] Package Manager Interception${NC}"
echo "     (Checking if commands route through Aikido wrappers)"
echo ""

# We check if the shell functions from safe-chain init exist.
# We source the init script in a subshell to test without modifying current shell.
if [ -f ~/.safe-chain/scripts/init-posix.sh ]; then
    # Test each command by checking if safe-chain defines a function for it
    for cmd in npm npx pnpm pnpx yarn bun bunx; do
        # Check if the command would resolve to a safe-chain wrapper function
        result=$(bash -c 'source ~/.safe-chain/scripts/init-posix.sh 2>/dev/null; type '"$cmd"' 2>&1')

        if echo "$result" | grep -q "function"; then
            # Check if there's an alias that would override the function
            alias_check=$(bash -ic "alias $cmd 2>/dev/null" 2>/dev/null)
            if [ -n "$alias_check" ]; then
                warn "$cmd: alias ($alias_check) overrides Aikido wrapper"
            else
                pass "$cmd -> Aikido wrapper (function)"
            fi
        else
            if ! command -v "$cmd" &> /dev/null; then
                echo -e "  ${BLUE}SKIP${NC}  $cmd: not installed"
            else
                fail "$cmd: not intercepted (resolves to $(command -v $cmd))"
            fi
        fi
    done
else
    for cmd in npm npx pnpm pnpx yarn bun bunx; do
        if command -v "$cmd" &> /dev/null; then
            fail "$cmd: not intercepted (safe-chain init missing)"
        fi
    done
fi

echo ""

# ── 3. Package Manager Configs ────────────────────────────────

echo -e "${BLUE}[3/7] Package Manager Configuration${NC}"

# npm
if [ -f ~/.npmrc ]; then
    if grep -q "ignore-scripts=true" ~/.npmrc; then
        pass "npm: ignore-scripts=true"
    else
        fail "npm: ignore-scripts not set in ~/.npmrc"
    fi
    if grep -q "save-exact=true" ~/.npmrc; then
        pass "npm: save-exact=true"
    else
        warn "npm: save-exact not set in ~/.npmrc"
    fi
else
    fail "npm: ~/.npmrc not found"
fi

# pnpm
if command -v pnpm &> /dev/null; then
    if [ -f ~/.pnpmrc ]; then
        if grep -q "ignore-scripts=true" ~/.pnpmrc; then
            pass "pnpm: ignore-scripts=true"
        else
            fail "pnpm: ignore-scripts not set in ~/.pnpmrc"
        fi
    else
        fail "pnpm: ~/.pnpmrc not found"
    fi
fi

# yarn
if command -v yarn &> /dev/null; then
    if [ -f ~/.yarnrc ]; then
        if grep -qF -- "--ignore-scripts true" ~/.yarnrc; then
            pass "yarn classic: --ignore-scripts true"
        else
            warn "yarn classic: --ignore-scripts not set in ~/.yarnrc"
        fi
    fi
    if [ -f ~/.yarnrc.yml ]; then
        if grep -q "enableScripts: false" ~/.yarnrc.yml; then
            pass "yarn modern: enableScripts: false"
        else
            warn "yarn modern: enableScripts not set in ~/.yarnrc.yml"
        fi
    fi
fi

# bun
if command -v bun &> /dev/null; then
    if [ -f ~/bunfig.toml ]; then
        if grep -q "exact = true" ~/bunfig.toml; then
            pass "bun: exact = true"
        else
            warn "bun: exact not set in ~/bunfig.toml"
        fi
    else
        fail "bun: ~/bunfig.toml not found"
    fi
fi

echo ""

# ── 4. npx-audit (CVE Scanner) ────────────────────────────────

echo -e "${BLUE}[4/7] npx-audit (CVE Scanner)${NC}"

npx_audit_installed=false

if command -v npx-audit &> /dev/null; then
    npx_audit_version=$(npx-audit --version 2>&1)
    pass "npx-audit installed ($npx_audit_version)"
    npx_audit_installed=true
else
    fail "npx-audit not installed — run: ./scripts/setup-security.sh"
fi

if [ -f ~/.config/npx-audit/init.sh ]; then
    pass "Shell wrappers exist (~/.config/npx-audit/init.sh)"
else
    fail "Shell wrappers missing (~/.config/npx-audit/init.sh)"
fi

# Check if init.sh is sourced in rc files
npx_audit_sourced=false
for rc_file in ~/.bashrc ~/.zshrc; do
    if [ -f "$rc_file" ] && grep -q 'npx-audit/init.sh' "$rc_file" 2>/dev/null; then
        pass "npx-audit sourced in $(basename $rc_file)"
        npx_audit_sourced=true
        break
    fi
done
if [ "$npx_audit_sourced" = false ]; then
    fail "npx-audit not sourced in any rc file"
fi

if [ -f ~/.config/npx-audit/config.json ]; then
    pass "Config exists (~/.config/npx-audit/config.json)"
else
    warn "Config missing — will use defaults"
fi

if [ -f ~/.config/npx-audit/allowlist.json ]; then
    local_count=$(jq '.packages | length' ~/.config/npx-audit/allowlist.json 2>/dev/null || echo "?")
    pass "Allowlist exists ($local_count packages)"
else
    warn "Allowlist missing — will be created on first scan"
fi

# Check wrapper precedence (npx-audit should override Aikido for npx)
if [ -f ~/.config/npx-audit/init.sh ] && [ -f ~/.safe-chain/scripts/init-posix.sh ]; then
    # Check that npx-audit init is sourced AFTER safe-chain in rc files
    for rc_file in ~/.bashrc ~/.zshrc; do
        if [ -f "$rc_file" ]; then
            sc_line=$(grep -n 'safe-chain' "$rc_file" 2>/dev/null | tail -1 | cut -d: -f1)
            na_line=$(grep -n 'npx-audit/init.sh' "$rc_file" 2>/dev/null | tail -1 | cut -d: -f1)
            if [ -n "$sc_line" ] && [ -n "$na_line" ]; then
                if [ "$na_line" -gt "$sc_line" ]; then
                    pass "Wrapper precedence correct in $(basename $rc_file) (npx-audit after Aikido)"
                else
                    warn "npx-audit sourced BEFORE Aikido in $(basename $rc_file) — CVE scanning may be bypassed"
                fi
                break
            fi
        fi
    done
fi

echo ""

# ── 5. SAST Tools (Static Analysis) ──────────────────────────

echo -e "${BLUE}[5/7] SAST Tools (Static Analysis)${NC}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
sast_available=0

# ESLint + security plugins
if command -v eslint &> /dev/null; then
    eslint_version=$(eslint --version 2>&1)
    pass "ESLint installed ($eslint_version)"
    if npm list -g eslint-plugin-security &>/dev/null 2>&1; then
        pass "eslint-plugin-security installed"
        sast_available=$((sast_available + 1))
    else
        warn "eslint-plugin-security not installed (npm install -g eslint-plugin-security)"
    fi
    if npm list -g eslint-plugin-no-unsanitized &>/dev/null 2>&1; then
        pass "eslint-plugin-no-unsanitized installed"
    else
        warn "eslint-plugin-no-unsanitized not installed (npm install -g eslint-plugin-no-unsanitized)"
    fi
else
    warn "ESLint not installed (optional: npm install -g eslint eslint-plugin-security eslint-plugin-no-unsanitized)"
fi

# Semgrep
if command -v semgrep &> /dev/null; then
    semgrep_version=$(semgrep --version 2>&1)
    pass "Semgrep installed ($semgrep_version)"
    sast_available=$((sast_available + 1))
else
    warn "Semgrep not installed (optional: pip3 install semgrep)"
fi

# js-x-ray
if node -e "require('@nodesecure/js-x-ray')" 2>/dev/null; then
    pass "js-x-ray (@nodesecure/js-x-ray) installed"
    sast_available=$((sast_available + 1))
else
    warn "js-x-ray not installed (optional: npm install -g @nodesecure/js-x-ray)"
fi

# Check for scan script and config
if [ -f "$SCRIPT_DIR/sast-scan.sh" ]; then
    pass "sast-scan.sh script present"
else
    warn "sast-scan.sh not found in scripts directory"
fi

if [ -f "$SCRIPT_DIR/../configs/eslint-security.config.mjs" ]; then
    pass "ESLint security config present (configs/eslint-security.config.mjs)"
else
    warn "configs/eslint-security.config.mjs not found"
fi

echo "     ($sast_available of 3 SAST tools available)"
echo ""

# ── 6. TypeScript Scanning ────────────────────────────────────

echo -e "${BLUE}[6/7] TypeScript Scanning${NC}"

ts_available=0

if [ -f "$SCRIPT_DIR/scan-ts-threats.sh" ]; then
    pass "scan-ts-threats.sh script present"
    ts_available=$((ts_available + 1))
else
    warn "scan-ts-threats.sh not found in scripts directory"
fi

if [ -f "$SCRIPT_DIR/check-npm-metadata.mjs" ]; then
    pass "check-npm-metadata.mjs script present"
    ts_available=$((ts_available + 1))
else
    warn "check-npm-metadata.mjs not found in scripts directory"
fi

if command -v jq &> /dev/null; then
    pass "jq available (required by TypeScript scanner)"
else
    warn "jq not installed (required by scan-ts-threats.sh)"
fi

echo "     ($ts_available of 2 TypeScript scanning tools available)"
echo ""

# ── 7. Coverage Gaps ──────────────────────────────────────────

echo -e "${BLUE}[7/7] Coverage Summary${NC}"
echo ""
echo "  Aikido Safe Chain scans for MALWARE (backdoors, crypto miners, data exfiltration)."
echo "  npx-audit scans for known CVE vulnerabilities in package dependency trees."
echo "  SAST tools scan SOURCE CODE for vulnerability patterns (eval, innerHTML, etc.)."
echo ""

if [ "$npx_audit_installed" = true ]; then
    echo "    Threat              | npm install | npx <pkg>   | pnpm/yarn/bun | Source Code"
    echo "    --------------------|-------------|-------------|---------------|-------------"
    echo "    Malware             | Aikido      | Aikido      | Aikido        | N/A"
    echo "    Known CVEs          | npm audit   | npx-audit   | pnpm/yarn aud | N/A"
    echo "    Code vulnerabilities| N/A         | N/A         | N/A           | sast-scan.sh"
    echo "    Build/TS threats    | N/A         | N/A         | N/A           | scan-ts-threats"
    echo "    Supply chain meta   | N/A         | N/A         | N/A           | check-npm-meta"
else
    echo "    Threat              | npm install | npx <pkg>   | pnpm/yarn/bun | Source Code"
    echo "    --------------------|-------------|-------------|---------------|-------------"
    echo "    Malware             | Aikido      | Aikido      | Aikido        | N/A"
    echo "    Known CVEs          | npm audit   | NOT COVERED | pnpm/yarn aud | N/A"
    echo "    Code vulnerabilities| N/A         | N/A         | N/A           | sast-scan.sh"
    echo "    Build/TS threats    | N/A         | N/A         | N/A           | scan-ts-threats"
    echo "    Supply chain meta   | N/A         | N/A         | N/A           | check-npm-meta"
    echo ""
    echo "  ⚠️  Install npx-audit to close the npx CVE gap:"
    echo "    ./scripts/setup-security.sh"
fi

if [ "$sast_available" -eq 0 ]; then
    echo ""
    echo "  ⚠️  No SAST tools installed. Install via ./scripts/setup-security.sh"
fi
echo ""

# ── Summary ───────────────────────────────────────────────────

echo "=========================================="
echo "Summary"
echo "=========================================="
echo -e "  ${GREEN}PASS: $pass_count${NC}  ${YELLOW}WARN: $warn_count${NC}  ${RED}FAIL: $fail_count${NC}"
echo ""

if [ $fail_count -gt 0 ]; then
    echo -e "${RED}Some checks failed.${NC} Run ./scripts/setup-security.sh to fix."
    exit 1
elif [ $warn_count -gt 0 ]; then
    echo -e "${YELLOW}Some warnings detected.${NC} Review items above."
    exit 0
else
    echo -e "${GREEN}All checks passed.${NC}"
    exit 0
fi
