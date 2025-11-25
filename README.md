# npm-security-tooling

**Automated security setup** for JavaScript package managers (npm, pnpm, yarn, bun). Hardens package manager configs and installs Aikido Safe Chain for supply chain protection.

**Why this script?** Aikido scans packages but doesn't configure package managers. This script does both: installs Aikido + configures all package managers to block lifecycle scripts and save exact versions (no `^` or `~` on new installs).

## 🛡️ How It Works

### Core Protection: Aikido Safe Chain (Primary Defense)

**Aikido Safe Chain is your primary security layer** - it automatically intercepts and scans ALL package manager operations:

- ✅ **npm** - Scans packages before installation
- ✅ **pnpm** - Scans packages before installation
- ✅ **yarn** - Scans packages before installation
- ✅ **bun** - Scans packages before installation

Aikido works by defining shell wrapper functions (via `safe-chain setup`) that intercept package manager commands and scan downloads in real-time against Aikido Intel.

### What Gets Configured

The setup script automatically:

1. **Installs Aikido Safe Chain** globally (required)
2. **Runs `safe-chain setup`** to create shell wrapper functions for npm, npx, pnpm, pnpx, yarn, bun, bunx
3. **Hardens all package managers** with security settings:
   - Disables lifecycle scripts (blocks malicious code execution)
   - Pins exact versions (prevents supply chain attacks)
   - Adds 24h minimum release age for pnpm/yarn/bun
   - Enables provenance for npm
4. **Optional:** Installs Socket Firewall for additional npm scanning

### What Aikido Does and Does NOT Cover

Aikido Safe Chain scans for **malware** (backdoors, crypto miners, data exfiltration). It does **not** scan for known CVE vulnerabilities — that's what `npm audit` does.

| Threat | `npm install` | `npx <pkg>` | `pnpm/yarn/bun` |
|---|---|---|---|
| Malware | Aikido | Aikido | Aikido |
| Known CVEs | `npm audit` | **NOT COVERED** | `pnpm/yarn audit` |

For CVE scanning of installed project dependencies, use `audit-all-projects.sh`. There is currently no tool that scans npx-invoked packages for CVEs — for high-risk npx packages, consider running them in a container.

## Contents

- `scripts/`
  - **`setup-security.sh`** – Automated setup: installs Aikido Safe Chain, runs `safe-chain setup` for shell integration, hardens all package manager configs
  - `audit-all-projects.sh` – Scans all projects with `npm audit`, generates timestamped logs and auto-fix scripts
  - `verify-security.sh` – Verifies that Aikido interception is active for all package managers (npm, npx, pnpm, yarn, bun)
- `docs/`
  - `NPM-SECURITY-SETUP.md` – Complete security guide covering:
    - Multi-package manager hardening (npm, pnpm, yarn, bun)
    - Aikido Safe Chain + optional Socket Firewall
    - Audit + fix workflow
    - Supply chain attack prevention strategies
    - Troubleshooting

## Related Resources

### Security Tools Used

This project integrates and configures:

- **Aikido Safe Chain** (PRIMARY) - Multi-package manager security wrapper
  - Protects npm, pnpm, yarn, AND bun
  - Required for comprehensive protection
  - Free and open-source
  https://github.com/AikidoSec/safe-chain

- **Socket Firewall** (OPTIONAL) - npm-specific threat intelligence enhancement
  - Additional layer for npm only (defense-in-depth)
  - Free to use
  - Complements Aikido for npm workflows
  https://socket.dev/blog/introducing-socket-firewall

### Best Practices Reference

This project's design and recommendations are heavily inspired by:

- **npm Security Best Practices (bodadotsh)**
  https://github.com/bodadotsh/npm-security-best-practices

That repository goes deep into:

- Lockfiles and version pinning
- Disabling lifecycle scripts
- Pre-install scanners
- Minimum release age
- Provenance and trusted publishing

## Quick Start

### 📦 Installation

**Recommended location** (matches other devtools):

```bash
cd ~
mkdir -p devtools
cd devtools

git clone https://github.com/Z7Lab/npm-security-tooling.git
cd npm-security-tooling
```

### 1. Initial Setup (Run Once)

**ONE COMMAND** - Everything is automated:

```bash
./scripts/setup-security.sh
```

**The script will:**

1. ✅ Check and install Aikido Safe Chain (required)
2. ✅ Run `safe-chain setup` to create shell wrappers for npm, npx, pnpm, yarn, bun
3. ✅ Configure npm with security settings + provenance
4. ✅ Configure pnpm with 24h minimum release age
5. ✅ Configure yarn (classic + modern) with 24h minimum release age
6. ✅ Configure bun with security settings
7. ✅ Ask if you want Socket Firewall (optional npm enhancement)
8. ✅ Backup all configs before changes

**You just answer the prompts** - the script does everything else.

```bash
# Restart your terminal after setup:
source ~/.bashrc

# Verify everything is working:
./scripts/verify-security.sh
```

### 2. Regular Security Audits

Scan your projects for known vulnerabilities using `npm audit`:

```bash
# Scan current directory
./scripts/audit-all-projects.sh

# Scan specific directory (recommended)
./scripts/audit-all-projects.sh ~/dev/projects
```

**Example output:**

```
==================================================================
NPM Security Audit - Sun Nov 24 07:00:00 PM EST 2025
==================================================================
Scanning directory: ~/dev/projects

✅ my-app: No vulnerabilities found
✅ api-server: No vulnerabilities found
⚠️  electron-app: 3 vulnerabilities (2 moderate, 1 high)

==================================================================
SUMMARY
==================================================================
Total projects scanned: 15
Clean projects: 12 ✅
Vulnerable projects: 3 ⚠️

📝 Auto-generated fix script: fix-vulnerabilities-2025-11-24_19-00-00.sh

To fix all vulnerabilities, run:
  ./scripts/fix-vulnerabilities-2025-11-24_19-00-00.sh
```

**Run the fix script:**

```bash
# Safe fixes only (recommended first)
./scripts/fix-vulnerabilities-YYYY-MM-DD_HH-MM-SS.sh

# If needed, include breaking changes
./scripts/fix-vulnerabilities-YYYY-MM-DD_HH-MM-SS.sh --force
```

**What if npm audit fix can't resolve a vulnerability?**

The audit script runs `npm audit`, which checks for known vulnerabilities in direct and **transitive dependencies** (dependencies of your dependencies). Sometimes `npm audit fix` cannot automatically update these due to parent package constraints.

**Solution:** Manually override the version in `package.json`

👉 **See detailed guide:** [When Audit Fix Can't Resolve Vulnerabilities](docs/NPM-SECURITY-SETUP.md#when-audit-fix-cant-resolve-vulnerabilities)

---

**Pro tip:** Create an alias for easy scanning:

```bash
# Add to ~/.bashrc
alias npm-audit='~/devtools/npm-security-tooling/scripts/audit-all-projects.sh ~/dev/projects'

# Then simply run:
npm-audit
```

---

## Platform-Specific Notes

### macOS

The setup script fully supports macOS:

```bash
# If using zsh (default on macOS), edit ~/.zshrc instead of ~/.bashrc
# The script handles both automatically

# macOS sed compatibility is handled automatically
# The script detects macOS and uses the correct sed syntax
```

### Windows

For Windows users:

1. **Use Git Bash or WSL** - The bash scripts require a Unix-like environment
2. **WSL (Recommended)** - Run the scripts in WSL Ubuntu:
   ```bash
   wsl
   cd /mnt/c/your/project/path
   ./scripts/setup-security.sh
   ```
3. **Git Bash** - Should work with minor path adjustments
4. **PowerShell Alternative** - Config files are the same, but you'll need to:
   - Manually install Aikido: `npm install -g @aikidosec/safe-chain`
   - Manually edit config files in `%USERPROFILE%` (`.npmrc`, `.pnpmrc`, etc.)
   - See `docs/NPM-SECURITY-SETUP.md` for config file contents

**Note:** These scripts are tested on Linux. Platform-specific issues may require manual config adjustments.

---

### 3. Daily Usage

All package managers are now automatically protected:

```bash
npm install express    # ✅ Protected by Aikido (malware scan)
npx create-next-app   # ✅ Protected by Aikido (malware scan)
pnpm install express   # ✅ Protected by Aikido (malware scan)
yarn add express       # ✅ Protected by Aikido (malware scan)
bun add express        # ✅ Protected by Aikido (malware scan)
```

To check that protection is still active at any time:

```bash
./scripts/verify-security.sh
```
