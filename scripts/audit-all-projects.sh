#!/bin/bash
# Automated npm security audit for all projects
# Run weekly or after package updates
#
# Usage:
#   ./audit-all-projects.sh              - Scans current directory
#   ./audit-all-projects.sh /path/to/dir - Scans specified directory

# Get the directory to scan
if [ -n "$1" ]; then
    # Use provided directory argument
    PROJECTS_DIR="$(cd "$1" && pwd)"
    if [ ! -d "$PROJECTS_DIR" ]; then
        echo "Error: Directory '$1' does not exist"
        exit 1
    fi
else
    # Default to current directory where script is run from
    PROJECTS_DIR="$(pwd)"
fi

# Get the directory where this script is located (for log/script output)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)
LOG_FILE="$SCRIPT_DIR/npm-audit-$TIMESTAMP.log"
FIX_SCRIPT="$SCRIPT_DIR/fix-vulnerabilities-$TIMESTAMP.sh"

echo "==================================================================" | tee -a "$LOG_FILE"
echo "NPM Security Audit - $(date)" | tee -a "$LOG_FILE"
echo "==================================================================" | tee -a "$LOG_FILE"
echo "Scanning directory: $PROJECTS_DIR" | tee -a "$LOG_FILE"
echo "Log file: $LOG_FILE" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Pre-flight: check Aikido Safe Chain status
if [ -f ~/.safe-chain/scripts/init-posix.sh ]; then
    echo "Aikido Safe Chain: active (shell integration configured)" | tee -a "$LOG_FILE"
else
    echo "WARNING: Aikido Safe Chain shell integration not configured." | tee -a "$LOG_FILE"
    echo "  Package manager commands (npm, npx, pnpm, yarn, bun) may not be" | tee -a "$LOG_FILE"
    echo "  intercepted for malware scanning. Run: safe-chain setup" | tee -a "$LOG_FILE"
fi
echo "" | tee -a "$LOG_FILE"
echo "NOTE: This audit scans installed project dependencies for known CVEs" | tee -a "$LOG_FILE"
echo "  using npm audit. Packages invoked via npx are NOT covered here." | tee -a "$LOG_FILE"
echo "  Aikido covers npx for malware, but not for CVE vulnerabilities." | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Counter for stats
total_projects=0
vulnerable_projects=0
clean_projects=0

# Initialize fix script
echo "#!/bin/bash" > "$FIX_SCRIPT"
echo "# Auto-generated vulnerability fix script" >> "$FIX_SCRIPT"
echo "# Generated: $(date)" >> "$FIX_SCRIPT"
echo "# Based on audit log: $(basename "$LOG_FILE")" >> "$FIX_SCRIPT"
echo "" >> "$FIX_SCRIPT"
echo "# Usage:" >> "$FIX_SCRIPT"
echo "#   ./$(basename "$FIX_SCRIPT")           - Safe fixes only" >> "$FIX_SCRIPT"
echo "#   ./$(basename "$FIX_SCRIPT") --force   - Include breaking changes" >> "$FIX_SCRIPT"
echo "" >> "$FIX_SCRIPT"
echo "FORCE_FLAG=\"\"" >> "$FIX_SCRIPT"
echo "if [ \"\$1\" == \"--force\" ]; then" >> "$FIX_SCRIPT"
echo "    FORCE_FLAG=\"--force\"" >> "$FIX_SCRIPT"
echo "    echo \"⚠️  Running with --force flag (may include breaking changes)\"" >> "$FIX_SCRIPT"
echo "    echo \"\"" >> "$FIX_SCRIPT"
echo "fi" >> "$FIX_SCRIPT"
echo "" >> "$FIX_SCRIPT"
echo "# Track results" >> "$FIX_SCRIPT"
echo "NEEDS_FORCE=()" >> "$FIX_SCRIPT"
echo "FIXED=()" >> "$FIX_SCRIPT"
echo "FAILED=()" >> "$FIX_SCRIPT"
echo "FAILED_ERRORS=()" >> "$FIX_SCRIPT"
echo "" >> "$FIX_SCRIPT"

# Find all directories with package.json (excluding node_modules)
while IFS= read -r package_file; do
    dir=$(dirname "$package_file")
    project_name=$(basename "$dir")

    # Skip if no node_modules (not installed)
    if [ ! -d "$dir/node_modules" ]; then
        continue
    fi

    ((total_projects++))

    echo "📦 Scanning: $project_name" | tee -a "$LOG_FILE"
    echo "   Path: $dir" | tee -a "$LOG_FILE"

    if ! cd "$dir"; then
        echo "   ⚠️  Skipped: Unable to access directory" | tee -a "$LOG_FILE"
        echo "" | tee -a "$LOG_FILE"
        continue
    fi

    # Run npm audit and capture output
    audit_output=$(npm audit --audit-level=moderate 2>&1)
    audit_exit_code=$?

    if [ $audit_exit_code -eq 0 ]; then
        echo "   ✅ No vulnerabilities found" | tee -a "$LOG_FILE"
        ((clean_projects++))
    else
        echo "   ⚠️  VULNERABILITIES DETECTED!" | tee -a "$LOG_FILE"
        echo "$audit_output" >> "$LOG_FILE"
        ((vulnerable_projects++))

        # Count severity levels
        critical=$(echo "$audit_output" | grep -oP '\d+(?= critical)' | head -1)
        high=$(echo "$audit_output" | grep -oP '\d+(?= high)' | head -1)
        moderate=$(echo "$audit_output" | grep -oP '\d+(?= moderate)' | head -1)

        [ -n "$critical" ] && echo "      🔴 Critical: $critical" | tee -a "$LOG_FILE"
        [ -n "$high" ] && echo "      🟠 High: $high" | tee -a "$LOG_FILE"
        [ -n "$moderate" ] && echo "      🟡 Moderate: $moderate" | tee -a "$LOG_FILE"

        # Add to fix script with framework detection
        echo "echo '=================================='" >> "$FIX_SCRIPT"
        echo "echo 'Fixing: $project_name'" >> "$FIX_SCRIPT"
        echo "echo 'Path: $dir'" >> "$FIX_SCRIPT"
        echo "echo '=================================='" >> "$FIX_SCRIPT"
        echo "cd '$dir'" >> "$FIX_SCRIPT"
        echo "PROJECT_DIR='$dir'" >> "$FIX_SCRIPT"
        echo "" >> "$FIX_SCRIPT"
        echo "# Try normal fix first" >> "$FIX_SCRIPT"
        echo "if [ -z \"\$FORCE_FLAG\" ]; then" >> "$FIX_SCRIPT"
        echo "    npm audit fix 2>&1 | tee /tmp/npm-fix-output.tmp" >> "$FIX_SCRIPT"
        echo "    EXIT_CODE=\${PIPESTATUS[0]}" >> "$FIX_SCRIPT"
        echo "    if grep -q \"npm audit fix --force\" /tmp/npm-fix-output.tmp; then" >> "$FIX_SCRIPT"
        echo "        echo \"⚠️  This project needs --force to fix breaking changes\"" >> "$FIX_SCRIPT"
        echo "        NEEDS_FORCE+=(\"$project_name ($dir)\")" >> "$FIX_SCRIPT"
        echo "    elif grep -q \"found 0 vulnerabilities\" /tmp/npm-fix-output.tmp; then" >> "$FIX_SCRIPT"
        echo "        FIXED+=(\"$project_name\")" >> "$FIX_SCRIPT"
        echo "    elif [ \$EXIT_CODE -ne 0 ]; then" >> "$FIX_SCRIPT"
        echo "        ERROR_MSG=\$(grep -E \"npm ERR!|error|Error|failed\" /tmp/npm-fix-output.tmp | head -3 | tr '\\n' ' ')" >> "$FIX_SCRIPT"
        echo "        FAILED+=(\"$project_name ($dir)\")" >> "$FIX_SCRIPT"
        echo "        FAILED_ERRORS+=(\"$project_name: \$ERROR_MSG\")" >> "$FIX_SCRIPT"
        echo "    else" >> "$FIX_SCRIPT"
        echo "        FAILED+=(\"$project_name ($dir)\")" >> "$FIX_SCRIPT"
        echo "        FAILED_ERRORS+=(\"$project_name: Unknown error - check npm output\")" >> "$FIX_SCRIPT"
        echo "    fi" >> "$FIX_SCRIPT"
        echo "else" >> "$FIX_SCRIPT"
        echo "    npm audit fix \$FORCE_FLAG 2>&1 | tee /tmp/npm-fix-output.tmp" >> "$FIX_SCRIPT"
        echo "    EXIT_CODE=\${PIPESTATUS[0]}" >> "$FIX_SCRIPT"
        echo "    if [ \$EXIT_CODE -eq 0 ]; then" >> "$FIX_SCRIPT"
        echo "        FIXED+=(\"$project_name\")" >> "$FIX_SCRIPT"
        echo "    else" >> "$FIX_SCRIPT"
        echo "        ERROR_MSG=\$(grep -E \"npm ERR!|error|Error|failed\" /tmp/npm-fix-output.tmp | head -3 | tr '\\n' ' ')" >> "$FIX_SCRIPT"
        echo "        FAILED+=(\"$project_name ($dir)\")" >> "$FIX_SCRIPT"
        echo "        FAILED_ERRORS+=(\"$project_name: \$ERROR_MSG\")" >> "$FIX_SCRIPT"
        echo "    fi" >> "$FIX_SCRIPT"
        echo "fi" >> "$FIX_SCRIPT"
        echo "echo ''" >> "$FIX_SCRIPT"
        echo "" >> "$FIX_SCRIPT"
    fi

    echo "" | tee -a "$LOG_FILE"

done < <(find "$PROJECTS_DIR" -name "package.json" -not -path "*/node_modules/*" -type f)

echo "==================================================================" | tee -a "$LOG_FILE"
echo "SUMMARY" | tee -a "$LOG_FILE"
echo "==================================================================" | tee -a "$LOG_FILE"
echo "Total projects scanned: $total_projects" | tee -a "$LOG_FILE"

if [ $total_projects -eq 0 ]; then
    echo "" | tee -a "$LOG_FILE"
    echo "⚠️  No projects found with package.json and node_modules/" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    echo "Tips:" | tee -a "$LOG_FILE"
    echo "  - Run 'npm install' in your projects first" | tee -a "$LOG_FILE"
    echo "  - Or specify a different directory: ./audit-all-projects.sh /path/to/projects" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    rm -f "$FIX_SCRIPT"
    exit 0
fi

echo "Clean projects: $clean_projects ✅" | tee -a "$LOG_FILE"
echo "Vulnerable projects: $vulnerable_projects ⚠️" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "Full log saved to: $LOG_FILE" | tee -a "$LOG_FILE"

if [ $vulnerable_projects -gt 0 ]; then
    # Finalize fix script with summary
    echo "# Cleanup" >> "$FIX_SCRIPT"
    echo "rm -f /tmp/npm-fix-output.tmp" >> "$FIX_SCRIPT"
    echo "" >> "$FIX_SCRIPT"
    echo "echo '=================================='" >> "$FIX_SCRIPT"
    echo "echo 'SUMMARY'" >> "$FIX_SCRIPT"
    echo "echo '=================================='" >> "$FIX_SCRIPT"
    echo "echo \"Fixed: \${#FIXED[@]} projects\"" >> "$FIX_SCRIPT"
    echo "echo \"Needs --force: \${#NEEDS_FORCE[@]} projects\"" >> "$FIX_SCRIPT"
    echo "echo \"Failed: \${#FAILED[@]} projects\"" >> "$FIX_SCRIPT"
    echo "echo ''" >> "$FIX_SCRIPT"
    echo "" >> "$FIX_SCRIPT"
    echo "if [ \${#FIXED[@]} -gt 0 ]; then" >> "$FIX_SCRIPT"
    echo "    echo \"✅ Fixed projects:\"" >> "$FIX_SCRIPT"
    echo "    for project in \"\${FIXED[@]}\"; do" >> "$FIX_SCRIPT"
    echo "        echo \"   - \$project\"" >> "$FIX_SCRIPT"
    echo "    done" >> "$FIX_SCRIPT"
    echo "    echo ''" >> "$FIX_SCRIPT"
    echo "    echo \"📋 Recommended: Clear build caches\"" >> "$FIX_SCRIPT"
    echo "    echo \"After updating dependencies, clear caches and rebuild:\"" >> "$FIX_SCRIPT"
    echo "    echo ''" >> "$FIX_SCRIPT"
    echo "fi" >> "$FIX_SCRIPT"
    echo "" >> "$FIX_SCRIPT"

    # Add cache cleanup detection and commands for each vulnerable project
    while IFS= read -r package_file; do
        dir_path=$(dirname "$package_file")
        proj_name=$(basename "$dir_path")

        # Skip if no node_modules
        if [ ! -d "$dir_path/node_modules" ]; then
            continue
        fi

        # Detect framework and add cache cleanup command
        echo "# Cache cleanup for: $proj_name" >> "$FIX_SCRIPT"
        echo "if [[ \" \${FIXED[@]} \" =~ \" $proj_name \" ]]; then" >> "$FIX_SCRIPT"
        echo "    echo \"   $proj_name ($dir_path):\"" >> "$FIX_SCRIPT"

        # Check for Next.js
        if grep -q '"next"' "$package_file" 2>/dev/null; then
            echo "    echo \"      cd $dir_path && rm -rf .next/ && npm run build\"" >> "$FIX_SCRIPT"
        # Check for Vite
        elif grep -q '"vite"' "$package_file" 2>/dev/null; then
            echo "    echo \"      cd $dir_path && rm -rf dist/ node_modules/.vite/ && npm run build\"" >> "$FIX_SCRIPT"
        # Check for CRA/React
        elif grep -q '"react-scripts"' "$package_file" 2>/dev/null; then
            echo "    echo \"      cd $dir_path && rm -rf build/ && npm run build\"" >> "$FIX_SCRIPT"
        # Check for Docusaurus
        elif grep -q '"@docusaurus/core"' "$package_file" 2>/dev/null; then
            echo "    echo \"      cd $dir_path && rm -rf build/ .docusaurus/ && npm run build\"" >> "$FIX_SCRIPT"
        # Check for Electron
        elif grep -q '"electron"' "$package_file" 2>/dev/null; then
            echo "    echo \"      cd $dir_path && rm -rf dist/ out/ && npm run build\"" >> "$FIX_SCRIPT"
        # Generic fallback
        else
            echo "    echo \"      cd $dir_path && rm -rf dist/ build/ .cache/ && npm run build\"" >> "$FIX_SCRIPT"
        fi
        echo "fi" >> "$FIX_SCRIPT"
    done < <(find "$PROJECTS_DIR" -name "package.json" -not -path "*/node_modules/*" -type f)

    echo "" >> "$FIX_SCRIPT"
    echo "if [ \${#NEEDS_FORCE[@]} -gt 0 ]; then" >> "$FIX_SCRIPT"
    echo "    echo \"⚠️  Projects needing --force (breaking changes):\"" >> "$FIX_SCRIPT"
    echo "    for project in \"\${NEEDS_FORCE[@]}\"; do" >> "$FIX_SCRIPT"
    echo "        echo \"   - \$project\"" >> "$FIX_SCRIPT"
    echo "    done" >> "$FIX_SCRIPT"
    echo "    echo ''" >> "$FIX_SCRIPT"
    echo "    echo \"To fix these with breaking changes, run:\"" >> "$FIX_SCRIPT"
    echo "    echo \"  $FIX_SCRIPT --force\"" >> "$FIX_SCRIPT"
    echo "    echo ''" >> "$FIX_SCRIPT"
    echo "fi" >> "$FIX_SCRIPT"
    echo "" >> "$FIX_SCRIPT"
    echo "if [ \${#FAILED[@]} -gt 0 ]; then" >> "$FIX_SCRIPT"
    echo "    echo \"❌ Failed projects:\"" >> "$FIX_SCRIPT"
    echo "    echo ''" >> "$FIX_SCRIPT"
    echo "    i=0" >> "$FIX_SCRIPT"
    echo "    for project in \"\${FAILED[@]}\"; do" >> "$FIX_SCRIPT"
    echo "        echo \"   \$project\"" >> "$FIX_SCRIPT"
    echo "        if [ \$i -lt \${#FAILED_ERRORS[@]} ]; then" >> "$FIX_SCRIPT"
    echo "            echo \"      Error: \${FAILED_ERRORS[\$i]}\"" >> "$FIX_SCRIPT"
    echo "        fi" >> "$FIX_SCRIPT"
    echo "        echo ''" >> "$FIX_SCRIPT"
    echo "        ((i++))" >> "$FIX_SCRIPT"
    echo "    done" >> "$FIX_SCRIPT"
    echo "    echo \"💡 Next steps for failed projects:\"" >> "$FIX_SCRIPT"
    echo "    echo \"   1. Check the error messages above\"" >> "$FIX_SCRIPT"
    echo "    echo \"   2. Try manually in the project directory:\"" >> "$FIX_SCRIPT"
    echo "    echo \"      cd /path/to/project\"" >> "$FIX_SCRIPT"
    echo "    echo \"      npm ci                    # Use lockfile (recommended)\"" >> "$FIX_SCRIPT"
    echo "    echo \"      npm audit fix             # Fix vulnerabilities\"" >> "$FIX_SCRIPT"
    echo "    echo \"   3. For pnpm/yarn projects:\"" >> "$FIX_SCRIPT"
    echo "    echo \"      pnpm install --frozen-lockfile && pnpm audit fix\"" >> "$FIX_SCRIPT"
    echo "    echo \"      yarn install --frozen-lockfile && yarn audit fix\"" >> "$FIX_SCRIPT"
    echo "    echo \"   4. Only if above fails, try clean reinstall:\"" >> "$FIX_SCRIPT"
    echo "    echo \"      rm -rf node_modules package-lock.json && npm install\"" >> "$FIX_SCRIPT"
    echo "    echo \"   5. Or check if dependencies have conflicts\"" >> "$FIX_SCRIPT"
    echo "    echo ''" >> "$FIX_SCRIPT"
    echo "fi" >> "$FIX_SCRIPT"

    chmod +x "$FIX_SCRIPT"

    echo "" | tee -a "$LOG_FILE"
    echo "⚠️  $vulnerable_projects projects need fixes" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    echo "📝 Auto-generated fix script: $FIX_SCRIPT" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    echo "To fix all vulnerabilities (safe fixes only):" | tee -a "$LOG_FILE"
    echo "  $FIX_SCRIPT" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    echo "To include breaking changes (use with caution):" | tee -a "$LOG_FILE"
    echo "  $FIX_SCRIPT --force" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    echo "Or review the script first:" | tee -a "$LOG_FILE"
    echo "  cat $FIX_SCRIPT" | tee -a "$LOG_FILE"
    exit 1
else
    # No vulnerabilities, remove empty fix script
    rm -f "$FIX_SCRIPT"
fi

exit 0
