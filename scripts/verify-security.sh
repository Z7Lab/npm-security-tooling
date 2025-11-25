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

echo -e "${BLUE}[1/4] Aikido Safe Chain${NC}"

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

echo -e "${BLUE}[2/4] Package Manager Interception${NC}"
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

echo -e "${BLUE}[3/4] Package Manager Configuration${NC}"

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

# ── 4. Coverage Gaps ──────────────────────────────────────────

echo -e "${BLUE}[4/4] Known Coverage Gaps${NC}"
echo ""
echo "  Aikido Safe Chain scans for MALWARE (backdoors, crypto miners, data exfiltration)."
echo "  It does NOT scan for known CVE vulnerabilities. Coverage breakdown:"
echo ""
echo "    Threat              | npm install | npx <pkg>   | pnpm/yarn/bun"
echo "    --------------------|-------------|-------------|---------------"
echo "    Malware             | Aikido      | Aikido      | Aikido"
echo "    Known CVEs          | npm audit   | NOT COVERED | pnpm/yarn audit"
echo ""
echo "  To scan installed project dependencies for CVEs:"
echo "    ./scripts/audit-all-projects.sh ~/dev/projects"
echo ""
echo "  There is currently no tool that scans npx-invoked packages for CVEs."
echo "  For high-risk npx packages, consider running them in a container."
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
