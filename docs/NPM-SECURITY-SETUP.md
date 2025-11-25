# NPM Security Setup Guide

This guide explains the security configurations automatically applied by `setup-security.sh` and how to use them effectively.

**Quick Start:** Run `./scripts/setup-security.sh` first, then reference this guide for daily usage and troubleshooting.

---

## Table of Contents

- [What Gets Configured](#what-gets-configured)
- [Multi-Package Manager Configuration](#multi-package-manager-configuration)
- [Multi-Package Manager Protection](#multi-package-manager-protection)
- [Automated Security Scanning](#automated-security-scanning)
- [Scripts in This Directory](#scripts-in-this-directory)
- [Daily Workflow](#daily-workflow)
- [When Audit Fix Can't Resolve Vulnerabilities](#when-audit-fix-cant-resolve-vulnerabilities)
- [Troubleshooting](#troubleshooting)

---

## What Gets Configured

### npm Security Settings

The setup script automatically configures these security settings in `~/.npmrc`:

```bash
ignore-scripts=true      # Blocks malicious lifecycle scripts
save-exact=true          # Pins exact package versions (no ^ or ~)
save-prefix=''           # Prevents version range operators
provenance=true          # Verifies package provenance when publishing
```

The script detects existing settings and only adds what's missing.

### Why These Settings Matter

**1. `ignore-scripts=true`** - **CRITICAL**

- Prevents packages from running arbitrary code during install
- Blocks common attack vectors like "Shai-Hulud" worm malware
- Malicious packages often use `postinstall` scripts to steal credentials

**2. `save-exact=true` & `save-prefix=''`**

- Locks packages to exact versions (e.g., `1.2.3` not `^1.2.3`)
- Prevents automatic minor/patch updates that could introduce compromised versions
- Ensures reproducible builds across environments

**3. `provenance=true`**

- Enables package verification for your own published packages
- Links packages to source code and build environments
- Uses Sigstore for cryptographic verification

### How to View Current Config

```bash
npm config list
cat ~/.npmrc
```

### Override Per-Project

If a specific project needs lifecycle scripts, create a local `.npmrc`:

```bash
# In project directory
echo "ignore-scripts=false" > .npmrc
```

---

## Multi-Package Manager Configuration

### Why This Matters

**Common attack pattern:**

Supply chain attacks often succeed by exploiting gaps in security configuration:

- npm is secured with `ignore-scripts=true`
- **pnpm, yarn, or bun are not configured** → malicious postinstall script executes
- Developer credentials stolen → supply chain compromised

Attackers will target whichever package manager lacks protection. Securing only npm is insufficient.

**All package managers need hardening**, not just npm.

### pnpm Configuration (~/.pnpmrc)

**The setup script automatically configures:**

```ini
ignore-scripts=true
save-exact=true
minimum-release-age=1440  # Wait 24 hours before installing new packages
```

The script:

- ✅ Detects if `~/.pnpmrc` exists
- ✅ Checks if each setting is already present
- ✅ Adds missing settings automatically
- ✅ Creates timestamped backup before changes

**Why minimum-release-age?** Waits 24 hours after a package is published before allowing installation. This gives the security community and automated scanning tools time to detect and report compromised packages before they reach your system. Most supply chain attacks are discovered and reported within 24-48 hours.

**Verify after running setup:**

```bash
cat ~/.pnpmrc
# Should show all three settings
```

### Yarn Configuration

**The setup script automatically configures both versions:**

**Yarn Classic (v1.x) - ~/.yarnrc:**

```ini
--ignore-scripts true
save-exact true
```

**Yarn Modern (v2+) - ~/.yarnrc.yml:**

```yaml
enableScripts: false
npmMinimalAgeGate: 1440 # Wait 24 hours before installing new packages
```

The script:

- ✅ Detects if config files exist
- ✅ Checks if settings are already present
- ✅ Adds missing settings automatically
- ✅ Creates timestamped backups before changes
- ✅ Handles both Yarn Classic and Modern

### Bun Configuration (~/bunfig.toml)

**The setup script automatically configures:**

```toml
[install]
exact = true                # Pin exact package versions
minimumReleaseAge = 86400   # Wait 24 hours (in seconds)
```

The script:

- ✅ Detects if `~/bunfig.toml` exists
- ✅ Checks if `[install]` section exists
- ✅ Adds missing settings automatically
- ✅ Creates timestamped backup before changes

**Note:** Bun disables lifecycle scripts by default (except for top 500 popular packages). The Aikido Safe Chain wrapper provides additional protection.

### Override Per-Project (any package manager)

If a specific project needs lifecycle scripts:

```bash
# npm project
echo "ignore-scripts=false" > .npmrc

# pnpm project
echo "ignore-scripts=false" > .pnpmrc

# yarn classic project
echo "--ignore-scripts false" > .yarnrc

# yarn modern project
echo "enableScripts: true" > .yarnrc.yml
```

---

## Multi-Package Manager Protection

### Primary Defense: Aikido Safe Chain (Recommended)

**Aikido Safe Chain** is a comprehensive security wrapper that protects ALL package managers:

- **Covers:** npm, pnpm, yarn, AND bun
- Scans packages for malware before installation
- Detects supply chain attacks in real-time
- Checks for typosquatting, install scripts, and suspicious code
- Automatic protection without aliases or configuration

**Why Aikido is recommended:**

Supply chain attacks often target alternate package managers (pnpm, yarn) that lack security protection while npm is secured. Aikido prevents this attack vector by protecting all package managers uniformly.

**Installation is automatic** - The `setup-security.sh` script installs Aikido Safe Chain for you. No manual installation needed.

### Optional Enhancement: Socket Firewall (npm-specific)

**Socket Firewall (`sfw`)** provides enhanced npm-only scanning:

- Additional threat intelligence layer for npm
- More mature threat database
- Defense-in-depth approach

**The setup script offers to install Socket Firewall** when you run it. Just answer "y" when prompted.

If Socket is already installed, the script will ask if you want to enable the npm alias for automatic protection.

### Usage

#### Aikido Safe Chain (Automatic Protection)

Once installed, Aikido automatically protects ALL package manager commands:

```bash
npm install express    # Protected by Aikido
pnpm install express   # Protected by Aikido
yarn add express       # Protected by Aikido
bun add express        # Protected by Aikido
```

**No aliases or configuration needed** - Aikido intercepts package managers transparently.

#### Socket Firewall (Optional Enhancement for npm)

The setup script handles Socket Firewall installation and configuration. When you run `./scripts/setup-security.sh`, it will:

1. Check if Socket Firewall is installed
2. Offer to install it if not present
3. Ask if you want the npm alias enabled (if already installed)
4. Configure the alias in both bash and zsh automatically

With Socket alias enabled, npm gets double protection:

```bash
npm install express
# Flow: Aikido scans → Socket scans → Install (two layers)

pnpm install express
# Flow: Aikido scans → Install (one layer, still protected)
```

### What You'll See

**With Aikido Safe Chain:**

Aikido runs silently in the background. If threats are detected, you'll see:

```
⚠️  Aikido Security Alert:
- Package contains suspicious install script
- Potential supply chain risk detected
```

**With Socket Firewall (if enabled for npm):**

```
Protected by Socket Firewall
✓ Scanning package for security issues...
✓ No threats detected
```

If threats are found:

```
⚠️  Security issues detected:
- High: Package contains install scripts
- Medium: Deprecated dependency
```

**Defense-in-Depth Mode (Aikido + Socket for npm):**

You'll see both Aikido and Socket scanning npm packages:

```
[Aikido scanning...]
Protected by Socket Firewall
✓ Both scanners passed
```

---

## Automated Security Scanning

### audit-all-projects.sh

**Location:** `scripts/audit-all-projects.sh` (can be run from anywhere)

Comprehensive security scanner that:

- Finds all projects with `package.json` in specified directory
- Runs `npm audit` on each project with `node_modules`
- Counts vulnerabilities by severity (Critical, High, Moderate)
- Generates timestamped log files
- Provides summary statistics

#### How to Run

```bash
# Scan current directory
./scripts/audit-all-projects.sh

# Scan specific directory
./scripts/audit-all-projects.sh ~/dev/projects

# Scan from any location with full path
/path/to/npm-security-tooling/scripts/audit-all-projects.sh ~/dev/projects

# Create an alias (add to ~/.bashrc)
alias npm-audit='~/devtools/npm-security-tooling/scripts/audit-all-projects.sh ~/dev/projects'
```

**Usage:**

```bash
# Default: Scans current directory
./audit-all-projects.sh

# With argument: Scans specified directory
./audit-all-projects.sh /path/to/your/projects
```

#### Auto-Generated Fix Script ⭐

**NEW:** When vulnerabilities are found, the audit script automatically generates a timestamped fix script!

The script will:

- Create `fix-vulnerabilities-YYYY-MM-DD_HH-MM-SS.sh`
- Include only projects with vulnerabilities
- Add proper error handling (`set -e`)
- Make it executable automatically
- Provide instructions on how to run it

#### Output Example

```
==================================================================
NPM Security Audit - Mon Nov 24 03:36:24 PM EST 2025
==================================================================

📦 Scanning: my-app
   Path: ~/dev/projects/my-app
   ✅ No vulnerabilities found

📦 Scanning: web-dashboard
   Path: ~/dev/projects/web-dashboard
   ⚠️  VULNERABILITIES DETECTED!
      🔴 Critical: 1
      🟠 High: 3
      🟡 Moderate: 2

==================================================================
SUMMARY
==================================================================
Total projects scanned: 17
Clean projects: 2 ✅
Vulnerable projects: 15 ⚠️

Full log saved to: ~/dev/projects/npm-audit-2025-11-24_15-36-24.log

⚠️  15 projects need fixes

📝 Auto-generated fix script: ~/dev/projects/fix-vulnerabilities-2025-11-24_15-43-39.sh

To fix all vulnerabilities, run:
  ~/dev/projects/fix-vulnerabilities-2025-11-24_15-43-39.sh

Or review the script first:
  cat ~/dev/projects/fix-vulnerabilities-2025-11-24_15-43-39.sh
```

#### Log Files

Log files are created with full timestamps:

- Format: `npm-audit-YYYY-MM-DD_HH-MM-SS.log`
- Example: `npm-audit-2025-11-24_15-36-24.log`
- Multiple scans per day create separate logs
- Logs contain full audit details for each vulnerable project

#### Option 1: Auto-Generated Fix Script (Recommended)

```bash
# Step 1: Run audit (generates fix script automatically)
./audit-all-projects.sh

# Step 2: Review what will be fixed (optional)
cat fix-vulnerabilities-2025-11-24_15-50-20.sh

# Step 3: Run safe fixes only (won't apply breaking changes)
./fix-vulnerabilities-2025-11-24_15-50-20.sh

# The script will tell you if any projects need --force
# Example output:
# ✅ Fixed: 10 projects
# ⚠️  Needs --force: 5 projects
#    - electron-app (/path/to/electron-app)
#    - web-dashboard (/path/to/web-dashboard)
# To fix these, run: ./fix-vulnerabilities-*.sh --force

# Step 4: If you want to apply breaking changes
./fix-vulnerabilities-2025-11-24_15-50-20.sh --force
```

#### Example Fix Script Output

When you run the fix script, you'll see helpful output for each project:

**Successful fix:**

```
==================================
Fixing: my-app
Path: ~/dev/projects/my-app
==================================
npm WARN deprecated lodash.get@4.4.2: This package is deprecated. Use optional chaining (?.) instead.

added 5 packages, removed 3 packages, and audited 245 packages in 4s

# npm audit report

found 0 vulnerabilities
```

**Project needing --force (breaking changes):**

```
==================================
Fixing: my-backend
Path: ~/dev/projects/my-backend
==================================

# npm audit report

axios  <=0.30.1
Severity: high
Axios Cross-Site Request Forgery Vulnerability - https://github.com/advisories/GHSA-wf5p-g6vw-rhxx
fix available via `npm audit fix --force`
Will install axios@1.6.0, which is a breaking change
node_modules/axios

3 high severity vulnerabilities

To address all issues (including breaking changes), run:
  npm audit fix --force
⚠️  This project needs --force to fix breaking changes
```

**Project missing lockfile:**

```
==================================
Fixing: legacy-app
Path: ~/dev/projects/legacy-app
==================================
npm ERR! code ENOLOCK
npm ERR! audit This command requires an existing lockfile.
npm ERR! audit Try creating one first with: npm i --package-lock-only
```

**Summary report:**

```
==================================
SUMMARY
==================================
Fixed: 5 projects
Needs --force: 2 projects
Failed: 1 projects

✅ Fixed projects:
   - my-app

⚠️  Projects needing --force (breaking changes):
   - my-backend (~/dev/projects/my-backend)
   - api-server (~/dev/projects/api-server)

To fix these with breaking changes, run:
  ./fix-vulnerabilities-2025-11-24_15-50-20.sh --force

❌ Failed projects:

   legacy-app (~/dev/projects/legacy-app)
      Error: npm ERR! code ENOLOCK npm ERR! audit This command requires an existing lockfile.

💡 Next steps for failed projects:
   1. Check the error messages above
   2. Try manually in the project directory:
      cd /path/to/project
      npm ci                    # Use lockfile (recommended)
      npm audit fix             # Fix vulnerabilities
   3. For pnpm/yarn projects:
      pnpm install --frozen-lockfile && pnpm audit fix
      yarn install --frozen-lockfile && yarn audit fix
   4. Only if above fails, try clean reinstall:
      rm -rf node_modules package-lock.json && npm install
   5. Or check if dependencies have conflicts
```

**Understanding the output:**

- npm shows **deprecated packages** - informational only
- **Severity levels** help prioritize fixes (critical > high > moderate > low)
- **"Will install X, which is a breaking change"** - means the fix may break your code
- **ENOLOCK errors** - project needs `package-lock.json` created first

#### Fix Scripts

Fix scripts are auto-generated when vulnerabilities are found:

- Format: `fix-vulnerabilities-YYYY-MM-DD_HH-MM-SS.sh`
- Example: `fix-vulnerabilities-2025-11-24_15-50-20.sh`
- Contains `npm audit fix` commands for only vulnerable projects
- Automatically made executable
- **Smart handling:**
  - Runs safe fixes first (no `--force`)
  - Detects which projects need `--force` for breaking changes
  - Continues even if some fixes fail
  - Tracks results: Fixed, Needs Force, Failed
- **Summary report** at the end showing what happened
- **Supports `--force` flag** to apply breaking changes
- If no vulnerabilities found, no fix script is created

**Example fix script contents:**

```bash
#!/bin/bash
# Auto-generated vulnerability fix script
# Generated: Mon Nov 24 03:50:20 PM EST 2025
# Based on audit log: npm-audit-2025-11-24_15-50-20.log

# Usage:
#   ./fix-vulnerabilities-*.sh           - Safe fixes only
#   ./fix-vulnerabilities-*.sh --force   - Include breaking changes

FORCE_FLAG=""
if [ "$1" == "--force" ]; then
    FORCE_FLAG="--force"
    echo "⚠️  Running with --force flag (may include breaking changes)"
fi

# Track results
NEEDS_FORCE=()
FIXED=()
FAILED=()

echo '=================================='
echo 'Fixing: electron-app'
echo 'Path: ~/dev/projects/electron-app'
echo '=================================='
cd '~/dev/projects/electron-app'

# Try normal fix first
if [ -z "$FORCE_FLAG" ]; then
    npm audit fix 2>&1 | tee /tmp/npm-fix-output.tmp
    if grep -q "npm audit fix --force" /tmp/npm-fix-output.tmp; then
        echo "⚠️  This project needs --force to fix breaking changes"
        NEEDS_FORCE+=("electron-app (~/dev/projects/electron-app)")
    elif grep -q "found 0 vulnerabilities" /tmp/npm-fix-output.tmp; then
        FIXED+=("electron-app")
    else
        FAILED+=("electron-app (~/dev/projects/electron-app)")
    fi
else
    npm audit fix $FORCE_FLAG
fi

# ... more projects ...

# Summary at the end
echo '=================================='
echo 'SUMMARY'
echo '=================================='
echo "Fixed: ${#FIXED[@]} projects"
echo "Needs --force: ${#NEEDS_FORCE[@]} projects"
echo "Failed: ${#FAILED[@]} projects"

if [ ${#NEEDS_FORCE[@]} -gt 0 ]; then
    echo "⚠️  Needs --force (breaking changes):"
    for project in "${NEEDS_FORCE[@]}"; do
        echo "   - $project"
    done
    echo "To fix these, run:"
    echo "  ./fix-vulnerabilities-*.sh --force"
fi
```

#### Schedule Regular Scans

Add to crontab for weekly scans:

```bash
# Edit crontab
crontab -e

# Add this line (runs every Monday at 9 AM)
0 9 * * 1 /path/to/npm-security-tooling/scripts/audit-all-projects.sh ~/dev/projects

# Or with your custom alias
0 9 * * 1 npm-audit
```

---

## Scripts in This Directory

### 1. setup-security.sh (RECOMMENDED - Run this first)

**Purpose:** Complete multi-package manager security setup

**What it does:**

- Installs Aikido Safe Chain globally
- Configures npm with security settings
- Configures pnpm with security settings (24h minimum release age)
- Configures yarn (classic + modern) with security settings
- Configures bun with security settings
- Optionally adds Socket Firewall for defense-in-depth
- Backs up all existing configs with timestamps
- Works with both bash and zsh

**Run once:**

```bash
./scripts/setup-security.sh
```

The script will:

1. Install Aikido Safe Chain (if not present)
2. Configure all package managers to block lifecycle scripts
3. Ask if you want Socket Firewall alias for enhanced npm scanning

**After running:**

```bash
# Open new terminal or
source ~/.bashrc

# Test protection
npm install lodash --dry-run    # Aikido protects
pnpm install lodash --dry-run   # Aikido protects
```

### 2. audit-all-projects.sh

**Purpose:** Scan all npm projects for vulnerabilities

**Features:**

- Location-agnostic (works from any directory)
- Timestamped logs
- Severity breakdown
- Summary statistics

**When to run:**

- After updating packages
- Before deploying to production
- Weekly/monthly security checks
- After hearing about new vulnerabilities

---

## Daily Workflow

### Installing New Packages

With Aikido Safe Chain installed, ALL package managers are automatically protected:

```bash
# npm - Protected by Aikido (+ Socket if enabled)
npm install <package-name>

# pnpm - Protected by Aikido (with 24h release delay)
pnpm install <package-name>

# yarn - Protected by Aikido (with 24h release delay)
yarn add <package-name>

# bun - Protected by Aikido (with 24h release delay)
bun add <package-name>
```

**Best practice - Clean installs:**

```bash
# ✅ RECOMMENDED: Keep lockfile, use ci/install command
npm ci                  # npm projects
pnpm install --frozen-lockfile  # pnpm projects
yarn install --frozen-lockfile  # yarn projects

# ⚠️  AVOID: Deleting lockfile causes slower installs and potential timeouts
rm -rf node_modules package-lock.json
npm install
```

Why lockfile-based installs are better:

- Uses lockfile for deterministic installs
- Faster and more reliable
- Better resilience to network timeouts
- Caches work between retries
- Prevents supply chain substitution attacks

### Updating Dependencies

```bash
# npm projects
npm update      # Aikido scans updated packages
npm outdated    # Check for outdated packages

# pnpm projects
pnpm update     # Aikido scans updated packages
pnpm outdated   # Check for outdated packages

# yarn projects
yarn upgrade    # Aikido scans updated packages
yarn outdated   # Check for outdated packages
```

### Fixing Vulnerabilities

```bash
# Check for vulnerabilities
npm audit

# Auto-fix compatible updates
npm audit fix

# Fix with breaking changes (use carefully)
npm audit fix --force
```

### Verify Package Signatures

**Critical security check** - Verify that packages haven't been tampered with:

```bash
# npm - Verify cryptographic signatures (npm 10+)
npm audit signatures

# pnpm - Check for vulnerabilities
pnpm audit

# yarn - Check for vulnerabilities
yarn audit
```

**What `npm audit signatures` does:**

- Verifies packages were published with provenance
- Checks cryptographic signatures from Sigstore
- Detects if packages were tampered with after publication
- Ensures packages match their source code

**Run this:**

- Before deploying to production
- After fresh installs
- Weekly as part of regular audits
- When suspicious activity is detected

### Before Committing

```bash
# Run project scan
./scripts/audit-all-projects.sh ~/dev/projects

# Verify lockfile integrity and signatures
npm audit signatures         # npm projects
pnpm audit                   # pnpm projects
yarn audit                   # yarn projects

# Always commit lockfiles
git add package-lock.json    # npm
git add pnpm-lock.yaml       # pnpm
git add yarn.lock            # yarn
```

---

## When Audit Fix Can't Resolve Vulnerabilities

### Manual Override for Transitive Dependencies

Sometimes `npm audit fix` cannot automatically update a vulnerable transitive dependency (a dependency of a dependency). When `npm audit` reports this, you'll need to manually force the fixed version.

**Workflow:**

1. Run `audit-all-projects.sh ~/dev/projects` → runs `npm audit` on each project
2. Run the generated fix script → `npm audit fix` attempts to fix vulnerabilities
3. If it fails with "cannot fix" → manually override the version

### How to Override

**For npm, pnpm, and bun** - Add `overrides` field in `package.json`:

```json
{
  "dependencies": {
    "library-a": "3.0.0"
  },
  "overrides": {
    "lodash": "4.17.21",
    "axios": "1.6.0"
  }
}
```

**For yarn** - Use `resolutions` field:

```json
{
  "resolutions": {
    "lodash": "4.17.21",
    "axios": "1.6.0"
  }
}
```

**Or use yarn CLI:**

```bash
yarn set resolution lodash 4.17.21
```

**Example scenario:**

- `npm audit` reports: `lodash@4.17.20` has vulnerability
- Parent package depends on `lodash@^4.17.0`
- `npm audit fix` fails: "cannot update due to parent constraints"
- **Solution:** Add override to force `lodash@4.17.21` everywhere

⚠️ **Test thoroughly** - overrides can break compatibility if the forced version is incompatible with the parent package.

---

## Troubleshooting

### Quick Reference

| Issue                                 | Solution                                                                                     |
| ------------------------------------- | -------------------------------------------------------------------------------------------- |
| Network timeouts with Socket Firewall | Use `npm ci` instead, retry install, [see details](#socket-firewall-network-timeout-errors)  |
| Socket Firewall not scanning packages | Check alias with `alias \| grep npm`, [see details](#socket-firewall-not-working)            |
| Package needs install scripts         | Override with `--ignore-scripts=false`, [see details](#package-install-fails-due-to-scripts) |
| Audit script finds no projects        | Ensure projects have `node_modules/`                                                         |

### Socket Firewall Not Working

**Check if installed:**

```bash
which sfw
sfw --version
```

**Check alias:**

```bash
alias | grep npm
# Should show: alias npm='sfw npm'
```

**Reload shell:**

```bash
source ~/.bashrc
# or open new terminal
```

### Socket Firewall Network Timeout Errors

**Symptoms:**

```
Socket Firewall encountered an unexpected error: AggregateError [ETIMEDOUT]
npm ERR! code ECONNRESET
npm ERR! errno ECONNRESET
npm ERR! network request to https://registry.npmjs.org/... failed
```

**What this means:**

- ✅ **Socket Firewall is working correctly**
- ⚠️ **This is a network connectivity issue, NOT a security block**
- Socket successfully scanned packages before the timeout occurred

**Common scenario:**

```bash
# After cleaning install
rm -rf node_modules package-lock.json
npm install
# Results in many timeout errors, even though Socket fetched 550+ packages
```

**Solutions (in order of preference):**

**1. Use `npm ci` with existing lockfile (Recommended)**

```bash
# Don't delete package-lock.json
npm ci
```

Benefits:

- Faster installation (uses lockfile)
- More reliable with Socket Firewall
- Deterministic builds
- If it fails partway, just retry - cached packages remain

**2. Simple retry**

If you see "550 packages fetched successfully" before errors:

```bash
npm ci
# Most packages are cached, retry completes quickly
```

**3. Increase network timeouts**

```bash
npm ci --fetch-timeout=60000 \
       --fetch-retry-mintimeout=20000 \
       --fetch-retry-maxtimeout=120000
```

**4. Disable IPv6 (if seeing ENETUNREACH 2606: errors)**

```bash
npm config set ipv6 false
npm ci
```

**5. Try different DNS resolver**

If timeouts persist to Cloudflare IPs (104.20.x.x, 172.66.x.x):

```bash
# Temporarily use Google DNS
sudo sh -c 'echo "nameserver 8.8.8.8" > /etc/resolv.conf'
npm ci
# Restore your DNS afterward
```

**When NOT to disable Socket Firewall:**

Network timeouts are **not a reason to disable security**. Socket Firewall:

- Fetches and scans packages successfully
- Times out due to npm registry connectivity, not security scanning
- Protects you from malicious packages during the install process

**How to tell the difference:**

| Network Issue                                     | Security Block                              |
| ------------------------------------------------- | ------------------------------------------- |
| `ETIMEDOUT`, `ECONNRESET`                         | `Security issues detected`                  |
| "Socket Firewall encountered an unexpected error" | `⚠️ High: Package contains install scripts` |
| Happens after many successful fetches             | Happens immediately when scanning package   |
| Retry usually succeeds                            | Retry fails with same security warning      |

### Package Install Fails Due to Scripts

If a legitimate package needs scripts:

**Per-project override:**

```bash
echo "ignore-scripts=false" > .npmrc
npm install
```

**One-time install:**

```bash
npm install <package> --ignore-scripts=false
```

### Audit Script Not Finding Projects

The script scans subdirectories for `package.json`. Ensure:

- Projects have `package.json` files
- Projects have `node_modules/` (run `npm install` first)

### Log Files Filling Up Disk

Manually clean old logs:

```bash
# Delete logs older than 30 days
find ~/dev/projects -name "npm-audit-*.log" -mtime +30 -delete
```

---

## Global NPM Packages

Check your globally installed packages:

```bash
npm list -g --depth=0
```

---

## Summary

### What's Protected Now

✅ Global npm configuration hardened
✅ Lifecycle scripts disabled (blocks Shai-Hulud type attacks)
✅ Exact version pinning enabled
✅ Socket Firewall installed and ready
✅ Automated scanning script created
✅ Timestamped audit logs
✅ Easy setup for alias protection

### Next Steps

1. Run `./scripts/audit-all-projects.sh ~/dev/projects` weekly to scan for new vulnerabilities
2. Fix remaining vulnerable projects with `npm audit fix`
3. Consider enabling Dependabot on GitHub repositories
4. Share this setup with your team
5. Keep Aikido Safe Chain updated: `npm update -g @aikidosec/safe-chain`

---

## Resources

### Security Tools

- [Aikido Safe Chain](https://github.com/AikidoSec/safe-chain) - Multi-package manager security wrapper
- [Socket Firewall](https://socket.dev/blog/introducing-socket-firewall) - npm-specific threat intelligence (free)

### Best Practices & Documentation

- [NPM Security Best Practices Guide](https://github.com/bodadotsh/npm-security-best-practices)
- [NPM Audit Docs](https://docs.npmjs.com/cli/v11/commands/npm-audit)
- [Sigstore](https://www.sigstore.dev/) - Package signing and verification
- [OpenSSF Scorecard](https://securityscorecards.dev/) - Security assessment tool
- [Palo Alto Networks - NPM Supply Chain Attack Analysis](https://www.paloaltonetworks.com/blog/cloud-security/npm-supply-chain-attack/)
