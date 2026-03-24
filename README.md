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
4. **Installs npx-audit** — CVE vulnerability scanner for npx, pnpm dlx, yarn dlx, bunx
5. **Optional:** Installs Socket Firewall for additional npm scanning

### Coverage Matrix

| Threat | `npm install` | `npx <pkg>` | `pnpm/yarn/bun` | Source Code |
|---|---|---|---|---|
| Malware | Socket¹ + Aikido² | Aikido² | Aikido² | N/A |
| Known CVEs | `npm audit`³ | `npx-audit`³ | `pnpm/yarn audit`³ | N/A |
| Code vulnerabilities | N/A | N/A | N/A | `sast-scan.sh` |
| Build/TS threats | N/A | N/A | N/A | `scan-ts-threats.sh` |
| Supply chain metadata | N/A | N/A | N/A | `check-npm-metadata.mjs` |

¹ Socket Firewall (optional) — dry-run scan using Socket.dev threat intelligence before install.
² Aikido Safe Chain — scans using Aikido threat intelligence. Performs the actual install for npm.
³ GitHub Advisory Database (GHSA).

When dual-scan is enabled, `npm install/ci/add` goes through both scanners (Socket dry-run first, then Aikido real install). Non-install commands route through Socket only. See `scripts/npm-dual-scan.sh`.

For CVE scanning of installed project dependencies, use `audit-all-projects.sh`.
For static analysis of your source code, use `sast-scan.sh`.

## Contents

- `scripts/`
  - **`setup-security.sh`** – Automated setup: installs Aikido Safe Chain + npx-audit + SAST tools, runs `safe-chain setup` for shell integration, hardens all package manager configs
  - `npx-audit` – CVE vulnerability scanner for npx, pnpm dlx, yarn dlx, bunx (installed to `~/.local/bin` by setup script)
  - `audit-all-projects.sh` – Scans all projects with `npm audit`, generates timestamped logs and auto-fix scripts
  - `sast-scan.sh` – Static analysis scanner: runs ESLint security rules, Semgrep, js-x-ray, and TypeScript threat scan against project source code
  - `js-x-ray-scan.mjs` – Node.js wrapper for js-x-ray (used by `sast-scan.sh`)
  - `scan-ts-threats.sh` – TypeScript/build tooling threat scanner (compiler plugins, @types audit, dangerous scripts, executable .d.ts)
  - `check-npm-metadata.mjs` – npm registry supply chain metadata checker (typosquatting, recent publishes, pulled packages, @types risks)
  - `harden-projects.sh` – Adds project-level `.npmrc` (ignore-scripts, save-exact, package-lock) so projects are protected on any machine, even without Aikido/Socket installed
  - `verify-security.sh` – Verifies that Aikido, npx-audit, SAST tools, and package manager configs are all active
- `configs/`
  - `eslint-security.config.mjs` – Standalone ESLint config with security-only rules (does not interfere with project ESLint configs)
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

- [**Aikido Safe Chain**](https://github.com/AikidoSec/safe-chain) (PRIMARY) - Multi-package manager security wrapper
  - Protects npm, pnpm, yarn, AND bun
  - Required for comprehensive protection
  - Free and open-source

- [**Socket Firewall**](https://socket.dev/blog/introducing-socket-firewall) (OPTIONAL) - npm-specific threat intelligence enhancement
  - Additional layer for npm only (defense-in-depth)
  - Free to use
  - Complements Aikido for npm workflows

### Best Practices Reference

This project's design and recommendations are heavily inspired by:

- [**npm Security Best Practices (bodadotsh)**](https://github.com/bodadotsh/npm-security-best-practices)

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
8. ✅ Install npx-audit for CVE scanning of npx/dlx packages
9. ✅ Ask if you want SAST tools (ESLint security, Semgrep, js-x-ray)
10. ✅ Backup all configs before changes

**You just answer the prompts** - the script does everything else.

```bash
# Restart your terminal after setup:
source ~/.bashrc

# Verify everything is working:
./scripts/verify-security.sh
```

**Expected output (all checks passing):**

```
==========================================
Security Verification Check
==========================================

[1/6] Aikido Safe Chain
  PASS  Aikido Safe Chain installed (x.x.x)
  PASS  Shell integration configured

[2/6] Package Manager Interception
  PASS  npm routes through Aikido wrapper
  PASS  npx routes through Aikido wrapper
  ...

[3/6] Package Manager Configuration
  PASS  npm: ignore-scripts=true
  PASS  npm: save-exact=true
  ...

[4/6] npx-audit (CVE Scanner)
  PASS  npx-audit installed (1.0.0)
  PASS  Shell wrappers exist
  ...

[5/6] SAST Tools (Static Analysis)
  PASS  ESLint installed
  PASS  eslint-plugin-security installed
  PASS  Semgrep installed
  PASS  js-x-ray installed
  ...

[6/6] Coverage Summary
  ...

==========================================
Summary
==========================================
  PASS: 16  WARN: 0  FAIL: 0

All checks passed.
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

If `npm audit fix` can't resolve a vulnerability, see [When Audit Fix Can't Resolve Vulnerabilities](docs/NPM-SECURITY-SETUP.md#when-audit-fix-cant-resolve-vulnerabilities).

### 3. Harden Projects (Portable Protection)

The setup script configures your *machine* (`~/.npmrc`), but those settings don't travel with your repos. If someone (or an agent) clones your project on an unconfigured machine, `npm install` runs with full default behavior — including install scripts.

`harden-projects.sh` fixes this by adding a project-level `.npmrc` to each project:

```bash
# Harden all projects in a directory
./scripts/harden-projects.sh ~/dev/projects
```

This adds a `.npmrc` to each project root with:

```ini
ignore-scripts=true    # Blocks malicious postinstall/preinstall hooks
save-exact=true        # Prevents semver range drift
package-lock=true      # Ensures lockfile is always used
```

**Commit the `.npmrc` files** — any `npm install` on *any* machine respects these settings, even without Aikido or Socket installed.

The script also checks for:
- Missing or uncommitted lockfiles
- `.npmrc` being gitignored (meaning it won't travel with the repo)
- Dangerous overrides (`ignore-scripts=false`) — fixable with `--fix-overrides`

---

**Pro tip:** Create an alias for easy scanning:

```bash
# Add to ~/.bashrc
alias npm-audit='~/devtools/npm-security-tooling/scripts/audit-all-projects.sh ~/dev/projects'

# Then simply run:
npm-audit
```

### 4. Daily Usage

All package managers are automatically protected:

```bash
npm install express    # ✅ Protected by Aikido (malware scan)
npx create-next-app   # ✅ Protected by npx-audit (CVE) + Aikido (malware)
pnpm install express   # ✅ Protected by Aikido (malware scan)
pnpm dlx create-app   # ✅ Protected by npx-audit (CVE) + Aikido (malware)
yarn add express       # ✅ Protected by Aikido (malware scan)
bun add express        # ✅ Protected by Aikido (malware scan)
```

To check that protection is still active at any time:

```bash
./scripts/verify-security.sh
```

### 5. Static Analysis (SAST) Scanning

Scan your source code for security vulnerabilities (eval, innerHTML, SQL injection, obfuscated code, etc.):

```bash
# Scan a single project
./scripts/sast-scan.sh ~/dev/projects/my-app

# Scan all projects in a directory
./scripts/sast-scan.sh ~/dev/projects

# Run only one tool
./scripts/sast-scan.sh --eslint-only ~/dev/projects/my-app
./scripts/sast-scan.sh --semgrep-only ~/dev/projects/my-app
./scripts/sast-scan.sh --js-x-ray-only ~/dev/projects/my-app

# JSON output (for CI integration)
./scripts/sast-scan.sh --json ~/dev/projects/my-app
```

**Tools used:**
- **ESLint + security plugins** — Detects `eval()`, `innerHTML`, SQL injection patterns, timing attacks
- **Semgrep** — Multi-language SAST with curated security rules (no login required)
- **js-x-ray** — Detects obfuscated code, encoded literals, unsafe imports

All tools are optional — the scan runs whichever tools are installed and reports combined results.

### 6. TypeScript Security Scanning

TypeScript projects have unique attack surfaces: compiler plugins execute at build time, `@types/` packages are maintained by different people than the base package, and build tool configs (Vite, Webpack, Rollup) can import malicious plugins with full system access.

```bash
# Scan a project for TypeScript/build tooling threats
./scripts/scan-ts-threats.sh ~/dev/projects/my-app

# Deep scan (thorough, slower — checks all @types and .d.ts files)
./scripts/scan-ts-threats.sh ~/dev/projects --deep

# Check npm supply chain metadata (typosquatting, recent publishes, @types risks)
node ./scripts/check-npm-metadata.mjs --dir ~/dev/projects/my-app

# JSON output for CI integration
node ./scripts/check-npm-metadata.mjs --lockfile package-lock.json --json
```

**What gets scanned:**
- **tsconfig.json** — Compiler plugins and custom transformers
- **Build configs** — Vite, Webpack, Rollup configs for dangerous patterns (eval, child_process, network calls)
- **@types/ packages** — Postinstall scripts, executable code in type-only packages
- **package.json scripts** — Suspicious commands (curl, wget, eval, encoded strings)
- **.d.ts files** — Executable code hidden in type declarations
- **npm registry metadata** — Typosquatting, recently published versions, pulled packages, missing repos

Both tools are also integrated into `sast-scan.sh` — run `--ts-threats-only` to run just the TypeScript checks.

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
