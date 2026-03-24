#!/bin/bash
# Static Application Security Testing (SAST) for JavaScript/TypeScript
# Runs ESLint security rules, Semgrep, and js-x-ray against project source code
#
# Usage:
#   ./sast-scan.sh                           - Scans current directory
#   ./sast-scan.sh /path/to/project          - Scans specified project
#   ./sast-scan.sh ~/dev/projects            - Scans all projects in directory
#   ./sast-scan.sh --eslint-only /path       - Run only ESLint security scan
#   ./sast-scan.sh --semgrep-only /path      - Run only Semgrep scan
#   ./sast-scan.sh --js-x-ray-only /path     - Run only js-x-ray scan
#   ./sast-scan.sh --ts-threats-only /path   - Run only TypeScript threat scan
#   ./sast-scan.sh --json /path              - JSON output to stdout

set -uo pipefail

# Colors (match verify-security.sh convention)
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# Script directory and timestamp
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)
LOG_FILE="$SCRIPT_DIR/logs/sast-scan-$TIMESTAMP.log"

# Parse flags
RUN_ESLINT=true
RUN_SEMGREP=true
RUN_JSXRAY=true
RUN_TS_THREATS=true
JSON_OUTPUT=false
TARGET_DIR=""

for arg in "$@"; do
    case "$arg" in
        --eslint-only)
            RUN_SEMGREP=false
            RUN_JSXRAY=false
            RUN_TS_THREATS=false
            ;;
        --semgrep-only)
            RUN_ESLINT=false
            RUN_JSXRAY=false
            RUN_TS_THREATS=false
            ;;
        --js-x-ray-only)
            RUN_ESLINT=false
            RUN_SEMGREP=false
            RUN_TS_THREATS=false
            ;;
        --ts-threats-only)
            RUN_ESLINT=false
            RUN_SEMGREP=false
            RUN_JSXRAY=false
            ;;
        --json)
            JSON_OUTPUT=true
            ;;
        -*)
            echo "Unknown flag: $arg"
            echo "Usage: ./sast-scan.sh [--eslint-only|--semgrep-only|--js-x-ray-only|--ts-threats-only] [--json] [directory]"
            exit 2
            ;;
        *)
            TARGET_DIR="$arg"
            ;;
    esac
done

# Resolve target directory
if [ -n "$TARGET_DIR" ]; then
    if [ ! -d "$TARGET_DIR" ]; then
        echo "Error: Directory '$TARGET_DIR' does not exist"
        exit 2
    fi
    TARGET_DIR="$(cd "$TARGET_DIR" && pwd)"
else
    TARGET_DIR="$(pwd)"
fi

# Logging helper
log() {
    if [ "$JSON_OUTPUT" = false ]; then
        echo -e "$1"
    fi
    echo -e "$1" | sed 's/\x1b\[[0-9;]*m//g' >> "$LOG_FILE"
}

# ── Tool availability checks ──────────────────────────────────

HAS_ESLINT=false
HAS_SEMGREP=false
HAS_JSXRAY=false
ESLINT_NO_CONFIG_FLAG="--no-eslintrc"

if [ "$RUN_ESLINT" = true ] && command -v eslint &> /dev/null; then
    # Check for security plugins
    if npm list -g eslint-plugin-security &>/dev/null 2>&1; then
        HAS_ESLINT=true
        # Detect ESLint version for correct flag
        eslint_major=$(eslint --version 2>&1 | grep -oP '^\d+' || echo "8")
        if [ "$eslint_major" -ge 10 ] 2>/dev/null; then
            ESLINT_NO_CONFIG_FLAG="--no-config-lookup"
        fi
    fi
fi

if [ "$RUN_SEMGREP" = true ] && command -v semgrep &> /dev/null; then
    HAS_SEMGREP=true
fi

if [ "$RUN_JSXRAY" = true ] && node -e "require('@nodesecure/js-x-ray')" 2>/dev/null; then
    HAS_JSXRAY=true
fi

HAS_TS_THREATS=false
if [ "$RUN_TS_THREATS" = true ] && [ -f "$SCRIPT_DIR/scan-ts-threats.sh" ]; then
    HAS_TS_THREATS=true
fi

# Check at least one tool is available
if [ "$HAS_ESLINT" = false ] && [ "$HAS_SEMGREP" = false ] && [ "$HAS_JSXRAY" = false ] && [ "$HAS_TS_THREATS" = false ]; then
    echo "Error: No SAST tools are installed."
    echo ""
    echo "Install with ./scripts/setup-security.sh or manually:"
    echo "  npm install -g eslint eslint-plugin-security eslint-plugin-no-unsanitized"
    echo "  pip3 install semgrep"
    echo "  npm install -g @nodesecure/js-x-ray"
    exit 2
fi

# ── Discover projects ─────────────────────────────────────────

projects=()

if [ -f "$TARGET_DIR/package.json" ]; then
    # Single project
    projects+=("$TARGET_DIR")
else
    # Find all projects in directory
    while IFS= read -r package_file; do
        projects+=("$(dirname "$package_file")")
    done < <(find "$TARGET_DIR" -maxdepth 3 -name "package.json" -not -path "*/node_modules/*" -type f 2>/dev/null)
fi

if [ ${#projects[@]} -eq 0 ]; then
    echo "No projects found with package.json in: $TARGET_DIR"
    exit 0
fi

# ── Header ────────────────────────────────────────────────────

log "=================================================================="
log "SAST Security Scan - $(date)"
log "=================================================================="
log "Directory: $TARGET_DIR"
log "Projects found: ${#projects[@]}"
log ""

tools_list=""
[ "$HAS_ESLINT" = true ] && tools_list+="ESLint "
[ "$HAS_SEMGREP" = true ] && tools_list+="Semgrep "
[ "$HAS_JSXRAY" = true ] && tools_list+="js-x-ray "
[ "$HAS_TS_THREATS" = true ] && tools_list+="ts-threats "
log "Tools: $tools_list"
[ "$HAS_ESLINT" = false ] && [ "$RUN_ESLINT" = true ] && log "${YELLOW}  ⚠️  ESLint not available (install: npm install -g eslint eslint-plugin-security eslint-plugin-no-unsanitized)${NC}"
[ "$HAS_SEMGREP" = false ] && [ "$RUN_SEMGREP" = true ] && log "${YELLOW}  ⚠️  Semgrep not available (install: pip3 install semgrep)${NC}"
[ "$HAS_JSXRAY" = false ] && [ "$RUN_JSXRAY" = true ] && log "${YELLOW}  ⚠️  js-x-ray not available (install: npm install -g @nodesecure/js-x-ray)${NC}"
log ""

# ── Counters ──────────────────────────────────────────────────

total_projects=0
projects_with_findings=0
clean_projects=0

# Per-tool finding counts
eslint_total=0; eslint_error=0; eslint_warning=0
semgrep_total=0; semgrep_error=0; semgrep_warning=0; semgrep_info=0
jsxray_total=0; jsxray_critical=0; jsxray_warning=0; jsxray_info=0
ts_total=0; ts_high=0; ts_medium=0; ts_low=0

# JSON accumulator
json_results="[]"

# ── Find source directories in a project ──────────────────────

find_src_dirs() {
    local project_dir="$1"
    local src_dirs=()

    for dir_name in src lib app pages server routes api; do
        if [ -d "$project_dir/$dir_name" ]; then
            src_dirs+=("$project_dir/$dir_name")
        fi
    done

    # If no standard dirs found, scan the project root (excluding node_modules etc.)
    if [ ${#src_dirs[@]} -eq 0 ]; then
        src_dirs+=("$project_dir")
    fi

    echo "${src_dirs[@]}"
}

# ── Per-project scan ──────────────────────────────────────────

for project_dir in "${projects[@]}"; do
    project_name=$(basename "$project_dir")
    total_projects=$((total_projects + 1))

    log "──────────────────────────────────────────"
    log "📦 ${BOLD}$project_name${NC}"
    log "   $project_dir"

    project_eslint=0
    project_semgrep=0
    project_jsxray=0
    project_eslint_err=0
    project_semgrep_err=0
    project_jsxray_crit=0

    # ── ESLint Security Scan ──

    if [ "$HAS_ESLINT" = true ]; then
        log "   ${BLUE}Running ESLint security scan...${NC}"

        eslint_config="$REPO_DIR/configs/eslint-security.config.mjs"

        # Build list of source directories
        read -ra src_dirs <<< "$(find_src_dirs "$project_dir")"

        eslint_output=$(eslint $ESLINT_NO_CONFIG_FLAG \
            --config "$eslint_config" \
            --format json \
            --no-error-on-unmatched-pattern \
            "${src_dirs[@]}" 2>/dev/null || true)

        if [ -n "$eslint_output" ] && echo "$eslint_output" | jq -e '.' &>/dev/null; then
            project_eslint_err=$(echo "$eslint_output" | jq '[.[].errorCount] | add // 0')
            project_eslint_warn=$(echo "$eslint_output" | jq '[.[].warningCount] | add // 0')
            project_eslint=$((project_eslint_err + project_eslint_warn))

            eslint_total=$((eslint_total + project_eslint))
            eslint_error=$((eslint_error + project_eslint_err))
            eslint_warning=$((eslint_warning + project_eslint_warn))

            if [ "$project_eslint" -gt 0 ]; then
                log "   ESLint:    ${YELLOW}$project_eslint findings${NC} ($project_eslint_err error, $project_eslint_warn warning)"
                # Log individual findings
                echo "$eslint_output" | jq -r '.[] | select(.errorCount > 0 or .warningCount > 0) | .filePath as $f | .messages[] | "      \(.severity | if . == 2 then "ERROR" else "WARN " end)  \(.ruleId // "unknown") at \($f | split("/") | last):\(.line)"' 2>/dev/null >> "$LOG_FILE"
            else
                log "   ESLint:    ${GREEN}clean${NC}"
            fi
        else
            log "   ESLint:    ${GREEN}clean${NC}"
        fi
    fi

    # ── Semgrep Scan ──

    if [ "$HAS_SEMGREP" = true ]; then
        log "   ${BLUE}Running Semgrep scan...${NC}"

        semgrep_output=$(semgrep scan \
            --config p/javascript \
            --config p/security-audit \
            --json --quiet \
            --exclude='node_modules' --exclude='dist' --exclude='build' \
            --exclude='.next' --exclude='coverage' --exclude='*.min.js' \
            "$project_dir" 2>/dev/null || true)

        if [ -n "$semgrep_output" ] && echo "$semgrep_output" | jq -e '.results' &>/dev/null; then
            project_semgrep=$(echo "$semgrep_output" | jq '.results | length')
            project_semgrep_err=$(echo "$semgrep_output" | jq '[.results[] | select(.extra.severity == "ERROR")] | length')
            project_semgrep_warn=$(echo "$semgrep_output" | jq '[.results[] | select(.extra.severity == "WARNING")] | length')
            project_semgrep_info=$(echo "$semgrep_output" | jq "[.results[] | select(.extra.severity != \"ERROR\" and .extra.severity != \"WARNING\")] | length")

            semgrep_total=$((semgrep_total + project_semgrep))
            semgrep_error=$((semgrep_error + project_semgrep_err))
            semgrep_warning=$((semgrep_warning + project_semgrep_warn))
            semgrep_info=$((semgrep_info + project_semgrep_info))

            if [ "$project_semgrep" -gt 0 ]; then
                log "   Semgrep:   ${YELLOW}$project_semgrep findings${NC} ($project_semgrep_err error, $project_semgrep_warn warning, $project_semgrep_info info)"
                echo "$semgrep_output" | jq -r '.results[] | "      \(.extra.severity | ascii_upcase)  \(.check_id | split(".") | last) at \(.path | split("/") | last):\(.start.line)"' 2>/dev/null >> "$LOG_FILE"
            else
                log "   Semgrep:   ${GREEN}clean${NC}"
            fi
        else
            log "   Semgrep:   ${GREEN}clean${NC}"
        fi
    fi

    # ── js-x-ray Scan ──

    if [ "$HAS_JSXRAY" = true ]; then
        log "   ${BLUE}Running js-x-ray scan...${NC}"

        jsxray_output=$(node "$SCRIPT_DIR/js-x-ray-scan.mjs" --dir "$project_dir" --json 2>/dev/null || true)

        if [ -n "$jsxray_output" ] && echo "$jsxray_output" | jq -e '.warnings' &>/dev/null; then
            project_jsxray=$(echo "$jsxray_output" | jq '.totalWarnings')
            project_jsxray_crit=$(echo "$jsxray_output" | jq '[.warnings[] | select(.severity == "Critical")] | length')
            project_jsxray_warn=$(echo "$jsxray_output" | jq '[.warnings[] | select(.severity == "Warning")] | length')
            project_jsxray_info=$(echo "$jsxray_output" | jq '[.warnings[] | select(.severity == "Information")] | length')

            jsxray_total=$((jsxray_total + project_jsxray))
            jsxray_critical=$((jsxray_critical + project_jsxray_crit))
            jsxray_warning=$((jsxray_warning + project_jsxray_warn))
            jsxray_info=$((jsxray_info + project_jsxray_info))

            if [ "$project_jsxray" -gt 0 ]; then
                log "   js-x-ray:  ${YELLOW}$project_jsxray findings${NC} ($project_jsxray_crit critical, $project_jsxray_warn warning, $project_jsxray_info info)"
                echo "$jsxray_output" | jq -r '.warnings[] | select(.severity != "Information") | "      \(.severity | ascii_upcase)  \(.kind) in \(.file)"' 2>/dev/null >> "$LOG_FILE"
            else
                log "   js-x-ray:  ${GREEN}clean${NC}"
            fi
        else
            log "   js-x-ray:  ${GREEN}clean${NC}"
        fi
    fi

    # ── TypeScript Threats Scan ──

    project_ts=0
    project_ts_high=0

    if [ "$HAS_TS_THREATS" = true ]; then
        log "   ${BLUE}Running TypeScript threat scan...${NC}"

        ts_output=$("$SCRIPT_DIR/scan-ts-threats.sh" "$project_dir" 2>/dev/null || true)
        # Count findings from output (lines starting with [HIGH], [MEDIUM], [LOW])
        project_ts_high=$(echo "$ts_output" | grep -c '^\[HIGH\]' 2>/dev/null || echo 0)
        project_ts_med=$(echo "$ts_output" | grep -c '^\[MEDIUM\]' 2>/dev/null || echo 0)
        project_ts_low=$(echo "$ts_output" | grep -c '^\[LOW\]' 2>/dev/null || echo 0)
        project_ts=$((project_ts_high + project_ts_med + project_ts_low))

        ts_total=$((ts_total + project_ts))
        ts_high=$((ts_high + project_ts_high))
        ts_medium=$((ts_medium + project_ts_med))
        ts_low=$((ts_low + project_ts_low))

        if [ "$project_ts" -gt 0 ]; then
            log "   ts-threats: ${YELLOW}$project_ts findings${NC} ($project_ts_high high, $project_ts_med medium, $project_ts_low low)"
        else
            log "   ts-threats: ${GREEN}clean${NC}"
        fi
    fi

    # Track project-level results
    project_total=$((project_eslint + project_semgrep + project_jsxray + project_ts))
    if [ "$project_total" -gt 0 ]; then
        projects_with_findings=$((projects_with_findings + 1))
    else
        clean_projects=$((clean_projects + 1))
    fi

    # Accumulate JSON results
    if [ "$JSON_OUTPUT" = true ]; then
        project_json=$(jq -n \
            --arg name "$project_name" \
            --arg path "$project_dir" \
            --argjson eslint "$project_eslint" \
            --argjson semgrep "$project_semgrep" \
            --argjson jsxray "$project_jsxray" \
            '{name: $name, path: $path, eslint: $eslint, semgrep: $semgrep, jsxray: $jsxray}')
        json_results=$(echo "$json_results" | jq --argjson p "$project_json" '. + [$p]')
    fi

    log ""
done

# ── Overall Summary ───────────────────────────────────────────

grand_total=$((eslint_total + semgrep_total + jsxray_total + ts_total))

if [ "$JSON_OUTPUT" = true ]; then
    jq -n \
        --argjson projects "$json_results" \
        --argjson totalProjects "$total_projects" \
        --argjson projectsWithFindings "$projects_with_findings" \
        --argjson cleanProjects "$clean_projects" \
        --argjson eslintTotal "$eslint_total" \
        --argjson semgrepTotal "$semgrep_total" \
        --argjson jsxrayTotal "$jsxray_total" \
        --argjson tsThreatsTotal "$ts_total" \
        --argjson grandTotal "$grand_total" \
        '{
            totalProjects: $totalProjects,
            projectsWithFindings: $projectsWithFindings,
            cleanProjects: $cleanProjects,
            findings: {eslint: $eslintTotal, semgrep: $semgrepTotal, jsxray: $jsxrayTotal, tsThreats: $tsThreatsTotal, total: $grandTotal},
            projects: $projects
        }'
else
    log "=================================================================="
    log "${BOLD}SAST SCAN SUMMARY${NC}"
    log "=================================================================="
    log "Total projects scanned: $total_projects"
    log "Projects with findings: $projects_with_findings"
    log "Clean projects: $clean_projects"
    log ""

    if [ "$grand_total" -gt 0 ]; then
        log "  Tool          | Total | Error/Critical | Warning | Info"
        log "  --------------|-------|----------------|---------|-----"
        [ "$HAS_ESLINT" = true ] && \
        log "  ESLint        | $(printf '%5d' $eslint_total) | $(printf '%14d' $eslint_error) | $(printf '%7d' $eslint_warning) |    -"
        [ "$HAS_SEMGREP" = true ] && \
        log "  Semgrep       | $(printf '%5d' $semgrep_total) | $(printf '%14d' $semgrep_error) | $(printf '%7d' $semgrep_warning) | $(printf '%4d' $semgrep_info)"
        [ "$HAS_JSXRAY" = true ] && \
        log "  js-x-ray      | $(printf '%5d' $jsxray_total) | $(printf '%14d' $jsxray_critical) | $(printf '%7d' $jsxray_warning) | $(printf '%4d' $jsxray_info)"
        [ "$HAS_TS_THREATS" = true ] && \
        log "  ts-threats    | $(printf '%5d' $ts_total) | $(printf '%14d' $ts_high) | $(printf '%7d' $ts_medium) | $(printf '%4d' $ts_low)"
        log "  --------------|-------|----------------|---------|-----"
        log "  TOTAL         | $(printf '%5d' $grand_total) |                |         |"
        log ""
    fi

    log "Full log: $LOG_FILE"
    log ""

    if [ "$grand_total" -eq 0 ]; then
        log "${GREEN}No security findings detected.${NC}"
    else
        log "${YELLOW}$grand_total findings across $projects_with_findings project(s).${NC}"
        log "Review the log file for details."
    fi
fi

# Exit codes: 0=clean, 1=findings exist, 2=tool error (handled above)
if [ "$grand_total" -gt 0 ]; then
    exit 1
fi
exit 0
