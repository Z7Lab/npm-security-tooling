#!/bin/bash
# Harden npm/pnpm projects with project-level .npmrc
# These settings travel with the repo and apply on ANY machine,
# even without Aikido Safe Chain or Socket Firewall installed.
#
# Usage:
#   ./harden-projects.sh              - Scans current directory
#   ./harden-projects.sh /path/to/dir - Scans specified directory

set -e

# Get the directory to scan
if [ -n "$1" ]; then
    PROJECTS_DIR="$(cd "$1" && pwd)"
    if [ ! -d "$PROJECTS_DIR" ]; then
        echo "Error: Directory '$1' does not exist"
        exit 1
    fi
else
    PROJECTS_DIR="$(pwd)"
fi

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo "=========================================="
echo "Project-Level Security Hardening"
echo "=========================================="
echo ""
echo "Scanning: $PROJECTS_DIR"
echo ""

# Settings to enforce in project .npmrc
# These are read by both npm and pnpm from the project root.
REQUIRED_SETTINGS=(
    "ignore-scripts=true"
    "save-exact=true"
    "package-lock=true"
)

# Counters
total=0
hardened=0
already_hardened=0
warnings=0
overridden=0

# Find all projects with package.json (excluding node_modules and .git)
while IFS= read -r package_file; do
    dir=$(dirname "$package_file")
    project_name=$(basename "$dir")
    npmrc_file="$dir/.npmrc"

    total=$((total + 1))

    echo -e "${BLUE}$project_name${NC} ($dir)"

    project_updated=false

    # --- .npmrc hardening ---

    # Create .npmrc if it doesn't exist
    if [ ! -f "$npmrc_file" ]; then
        touch "$npmrc_file"
    fi

    # Check for dangerous overrides (someone explicitly set ignore-scripts=false)
    if grep -q "^ignore-scripts=false" "$npmrc_file" 2>/dev/null; then
        echo -e "   ${RED}!! .npmrc has ignore-scripts=false (scripts WILL run)${NC}"
        echo -e "      If this is intentional (native modules), add a comment explaining why."
        echo -e "      Otherwise, remove that line or run this script with --fix-overrides"
        overridden=$((overridden + 1))
        warnings=$((warnings + 1))

        if [ "${2:-}" = "--fix-overrides" ]; then
            if [[ "$OSTYPE" == "darwin"* ]]; then
                sed -i '' 's/^ignore-scripts=false/ignore-scripts=true/' "$npmrc_file"
            else
                sed -i 's/^ignore-scripts=false/ignore-scripts=true/' "$npmrc_file"
            fi
            echo -e "   ${GREEN}   -> Fixed: ignore-scripts set back to true${NC}"
            project_updated=true
        fi
    fi

    # Add each required setting if the key is missing entirely
    for setting in "${REQUIRED_SETTINGS[@]}"; do
        key="${setting%%=*}"
        if ! grep -q "^${key}=" "$npmrc_file" 2>/dev/null; then
            echo "$setting" >> "$npmrc_file"
            project_updated=true
        fi
    done

    if [ "$project_updated" = true ]; then
        echo -e "   ${GREEN}+ .npmrc hardened${NC}"
        hardened=$((hardened + 1))
    else
        echo -e "   ${GREEN}= .npmrc already hardened${NC}"
        already_hardened=$((already_hardened + 1))
    fi

    # --- Lockfile check ---

    has_lockfile=false
    lockfile_name=""
    if [ -f "$dir/package-lock.json" ]; then
        has_lockfile=true
        lockfile_name="package-lock.json"
    elif [ -f "$dir/pnpm-lock.yaml" ]; then
        has_lockfile=true
        lockfile_name="pnpm-lock.yaml"
    elif [ -f "$dir/yarn.lock" ]; then
        has_lockfile=true
        lockfile_name="yarn.lock"
    elif [ -f "$dir/bun.lockb" ] || [ -f "$dir/bun.lock" ]; then
        has_lockfile=true
        lockfile_name="bun.lock*"
    fi

    if [ "$has_lockfile" = true ]; then
        # Check if lockfile is git-tracked
        if git -C "$dir" ls-files --error-unmatch "$lockfile_name" &>/dev/null 2>&1; then
            echo -e "   ${GREEN}= $lockfile_name committed${NC}"
        else
            echo -e "   ${YELLOW}! $lockfile_name exists but is NOT committed${NC}"
            echo -e "      Run: cd $dir && git add $lockfile_name"
            warnings=$((warnings + 1))
        fi
    else
        echo -e "   ${YELLOW}! No lockfile found${NC}"
        echo -e "      Run: cd $dir && npm install --package-lock-only --ignore-scripts"
        warnings=$((warnings + 1))
    fi

    # --- .gitignore check: make sure .npmrc is NOT gitignored ---
    # Walk up from project dir checking each .gitignore
    npmrc_ignored=false
    check_dir="$dir"
    while [ "$check_dir" != "/" ]; do
        if [ -f "$check_dir/.gitignore" ]; then
            # Check common patterns that would exclude .npmrc
            if grep -qE '^\\.npmrc$|^\*\\.npmrc$' "$check_dir/.gitignore" 2>/dev/null; then
                npmrc_ignored=true
                echo -e "   ${RED}!! .npmrc is gitignored by $check_dir/.gitignore${NC}"
                echo -e "      The hardened .npmrc won't travel with the repo!"
                echo -e "      Remove '.npmrc' from that .gitignore, or add '!.npmrc' to override"
                warnings=$((warnings + 1))
                break
            fi
        fi
        check_dir=$(dirname "$check_dir")
    done

    echo ""

done < <(find "$PROJECTS_DIR" -name "package.json" \
    -not -path "*/node_modules/*" \
    -not -path "*/.git/*" \
    -type f)

# Summary
echo "=========================================="
echo "SUMMARY"
echo "=========================================="
echo "Total projects:   $total"
echo -e "Hardened (new):   $hardened"
echo -e "Already hardened: $already_hardened"

if [ $overridden -gt 0 ]; then
    echo -e "${RED}Overrides found:  $overridden (ignore-scripts=false)${NC}"
fi

if [ $warnings -gt 0 ]; then
    echo -e "${YELLOW}Warnings:         $warnings${NC}"
fi

echo ""

if [ $total -eq 0 ]; then
    echo "No projects with package.json found in $PROJECTS_DIR"
    echo ""
    echo "Usage: ./harden-projects.sh /path/to/your/projects"
    exit 0
fi

echo "What project-level .npmrc protects (even WITHOUT security tooling):"
echo "  ignore-scripts=true  Blocks malicious postinstall/preinstall hooks"
echo "  save-exact=true      Prevents semver range drift on future installs"
echo "  package-lock=true    Ensures lockfile is always generated/used"
echo ""

if [ $warnings -gt 0 ]; then
    echo "Fix warnings above for full protection:"
    echo "  - Missing lockfiles: npm install --package-lock-only --ignore-scripts"
    echo "  - Uncommitted lockfiles: git add <lockfile>"
    echo "  - .npmrc gitignored: remove that rule so hardening travels with the repo"
    echo ""
fi

if [ $overridden -gt 0 ]; then
    echo "To force-fix projects that have ignore-scripts=false:"
    echo "  ./harden-projects.sh $PROJECTS_DIR --fix-overrides"
    echo ""
fi

echo "Next steps:"
echo "  1. Commit the .npmrc files to each project"
echo "  2. Commit any lockfiles that aren't tracked"
echo "  3. Any 'npm install' on ANY machine respects these settings"
echo ""
echo "Limitations:"
echo "  - Yarn (v2+) and Bun use separate config files (.yarnrc.yml, bunfig.toml)"
echo "    that are not handled by this script. Add enableScripts: false to .yarnrc.yml"
echo "    or [install] exact = true to bunfig.toml manually if needed."
echo "  - Projects with native modules (node-gyp) may need ignore-scripts=false."
echo "    In that case, add a comment to .npmrc explaining why, and ensure Aikido"
echo "    Safe Chain is installed on the machine running the build."
echo ""
