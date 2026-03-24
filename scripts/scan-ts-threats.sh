#!/bin/bash
# TypeScript/build tooling threat scanner
# Scans for malicious compiler plugins, build config injection, @types abuse,
# suspicious package.json scripts, and executable code in .d.ts files
#
# Usage:
#   ./scripts/scan-ts-threats.sh                        # Scan current directory
#   ./scripts/scan-ts-threats.sh ~/dev                  # Scan specific directory
#   ./scripts/scan-ts-threats.sh ~/dev --deep           # Full @types + .d.ts scan
#   ./scripts/scan-ts-threats.sh ~/dev --skip-metadata  # Skip @types metadata checks

set -uo pipefail

# Colors (match verify-security.sh convention)
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# Config
SCAN_DIR="${1:-.}"
DEEP_MODE=false
SKIP_METADATA=false
for arg in "$@"; do
    [[ "$arg" == "--deep" ]] && DEEP_MODE=true
    [[ "$arg" == "--skip-metadata" ]] && SKIP_METADATA=true
done

# Filter out flags from SCAN_DIR
if [[ "$SCAN_DIR" == --* ]]; then
    SCAN_DIR="."
fi

# Script directory and timestamp
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)
LOG_FILE="$SCRIPT_DIR/output/ts-threats-$TIMESTAMP.log"

# Ensure output directory exists
mkdir -p "$SCRIPT_DIR/output"

# Counters
TOTAL_PROJECTS=0
TSCONFIG_FINDINGS=0
BUILD_CONFIG_FINDINGS=0
TYPES_FINDINGS=0
SCRIPT_FINDINGS=0
DTS_FINDINGS=0
HIGH_COUNT=0
MEDIUM_COUNT=0
LOW_COUNT=0

log() {
    echo -e "$1" | tee -a "$LOG_FILE"
}

# Resolve scan directory
SCAN_DIR=$(cd "$SCAN_DIR" 2>/dev/null && pwd || echo "$SCAN_DIR")

if [[ ! -d "$SCAN_DIR" ]]; then
    echo "Error: Directory not found: $SCAN_DIR"
    exit 1
fi

# Pre-flight checks
if ! command -v jq &>/dev/null; then
    echo "ERROR: jq not found. Install: sudo apt install jq / brew install jq"
    exit 2
fi

# Header
log ""
log "=================================================================="
log "  TypeScript Threat Scanner — $(date)"
log "=================================================================="
log "  Scanning: $SCAN_DIR"
if [[ "$DEEP_MODE" == true ]]; then
    log "  Mode: ${YELLOW}DEEP${NC} (full @types + .d.ts scan)"
else
    log "  Mode: default (fast scan)"
fi
log ""

# ── Stage 1/5: tsconfig.json Compiler Plugins ─────────────────

log "──────────────────────────────────────────────────────────────────"
log "  Stage 1/5: tsconfig.json Compiler Plugins"
log "──────────────────────────────────────────────────────────────────"
log ""

stage1_found=0

while IFS= read -r tsconfig; do
    [[ -z "$tsconfig" ]] && continue

    project_rel="${tsconfig#"$SCAN_DIR"/}"

    # Check if compilerOptions.plugins exists and is non-empty
    plugins_json=$(jq -r '.compilerOptions.plugins // empty' "$tsconfig" 2>/dev/null)

    if [[ -n "$plugins_json" ]] && [[ "$plugins_json" != "null" ]] && [[ "$plugins_json" != "[]" ]]; then
        plugin_count=$(echo "$plugins_json" | jq 'length' 2>/dev/null)
        plugin_count=${plugin_count:-0}

        if [[ $plugin_count -gt 0 ]]; then
            # Check each plugin
            for i in $(seq 0 $((plugin_count - 1))); do
                plugin_name=$(echo "$plugins_json" | jq -r ".[$i].transform // .[$i].name // \"unknown\"" 2>/dev/null)
                has_transform=$(echo "$plugins_json" | jq -r ".[$i].transform // empty" 2>/dev/null)

                if [[ -n "$has_transform" ]]; then
                    log "  ${RED}[HIGH]${NC} $project_rel: compiler plugin with transform '${has_transform}'"
                    HIGH_COUNT=$((HIGH_COUNT + 1))
                    stage1_found=$((stage1_found + 1))
                else
                    log "  ${YELLOW}[MEDIUM]${NC} $project_rel: compiler plugin '${plugin_name}'"
                    MEDIUM_COUNT=$((MEDIUM_COUNT + 1))
                    stage1_found=$((stage1_found + 1))
                fi
            done
        fi
    else
        log "  ${GREEN}+${NC} $project_rel: no compiler plugins"
    fi

    TOTAL_PROJECTS=$((TOTAL_PROJECTS + 1))

done < <(find "$SCAN_DIR" -maxdepth 4 -type f -name "tsconfig*.json" \
    ! -path "*/node_modules/*" \
    ! -path "*/.git/*" \
    2>/dev/null)

TSCONFIG_FINDINGS=$stage1_found
log ""

# ── Stage 2/5: Build Tool Configuration ───────────────────────

log "──────────────────────────────────────────────────────────────────"
log "  Stage 2/5: Build Tool Configuration"
log "──────────────────────────────────────────────────────────────────"
log ""

stage2_found=0

while IFS= read -r config_file; do
    [[ -z "$config_file" ]] && continue

    config_rel="${config_file#"$SCAN_DIR"/}"
    file_findings=0

    # HIGH: eval / Function constructor
    if grep -qE '\beval\s*\(|\bFunction\s*\(|\bnew\s+Function\b' "$config_file" 2>/dev/null; then
        log "  ${RED}[HIGH]${NC} $config_rel: eval() or Function() constructor"
        HIGH_COUNT=$((HIGH_COUNT + 1))
        file_findings=$((file_findings + 1))
    fi

    # HIGH: child_process usage
    if grep -qE '\bchild_process\b|\bexecSync\b|\bspawnSync\b' "$config_file" 2>/dev/null; then
        log "  ${RED}[HIGH]${NC} $config_rel: child_process / execSync / spawnSync"
        HIGH_COUNT=$((HIGH_COUNT + 1))
        file_findings=$((file_findings + 1))
    fi

    # HIGH: network access
    if grep -qE '\bfetch\s*\(|\bhttp\.get\b|\bhttps\.get\b|\bnet\.connect\b' "$config_file" 2>/dev/null; then
        log "  ${RED}[HIGH]${NC} $config_rel: network access (fetch/http/net)"
        HIGH_COUNT=$((HIGH_COUNT + 1))
        file_findings=$((file_findings + 1))
    fi

    # MEDIUM: long base64 strings
    if grep -qE '[A-Za-z0-9+/]{40,}' "$config_file" 2>/dev/null; then
        log "  ${YELLOW}[MEDIUM]${NC} $config_rel: long base64-like string"
        MEDIUM_COUNT=$((MEDIUM_COUNT + 1))
        file_findings=$((file_findings + 1))
    fi

    if [[ $file_findings -eq 0 ]]; then
        log "  ${GREEN}+${NC} $config_rel: clean"
    fi

    stage2_found=$((stage2_found + file_findings))

done < <(find "$SCAN_DIR" -maxdepth 3 -type f \( \
    -name "vite.config.*" -o \
    -name "webpack.config.*" -o \
    -name "rollup.config.*" -o \
    -name "esbuild.config.*" -o \
    -name "turbo.json" \
    \) ! -path "*/node_modules/*" ! -path "*/.git/*" 2>/dev/null)

BUILD_CONFIG_FINDINGS=$stage2_found
log ""

# ── Stage 3/5: @types/ Package Audit ──────────────────────────

log "──────────────────────────────────────────────────────────────────"
log "  Stage 3/5: @types/ Package Audit"
log "──────────────────────────────────────────────────────────────────"
log ""

stage3_found=0

# Collect @types packages to check
check_types_package() {
    local types_dir="$1"
    local pkg_name
    pkg_name=$(basename "$types_dir")
    local pkg_json="$types_dir/package.json"

    if [[ ! -f "$pkg_json" ]]; then
        return
    fi

    local findings=0

    # HIGH: lifecycle scripts
    local has_lifecycle
    has_lifecycle=$(jq -r '
        .scripts // {} |
        to_entries[] |
        select(.key == "postinstall" or .key == "preinstall" or .key == "prepare") |
        .key' "$pkg_json" 2>/dev/null)

    if [[ -n "$has_lifecycle" ]]; then
        log "  ${RED}[HIGH]${NC} @types/$pkg_name: lifecycle scripts (${has_lifecycle})"
        HIGH_COUNT=$((HIGH_COUNT + 1))
        findings=$((findings + 1))
    fi

    # HIGH: native addon indicators
    if [[ -f "$types_dir/binding.gyp" ]]; then
        log "  ${RED}[HIGH]${NC} @types/$pkg_name: contains binding.gyp (native addon)"
        HIGH_COUNT=$((HIGH_COUNT + 1))
        findings=$((findings + 1))
    fi

    # MEDIUM: contains executable JS files (not just .d.ts)
    local js_files
    js_files=$(find "$types_dir" -maxdepth 2 -type f \( -name "*.js" -o -name "*.mjs" -o -name "*.cjs" \) 2>/dev/null | head -5)
    if [[ -n "$js_files" ]]; then
        log "  ${YELLOW}[MEDIUM]${NC} @types/$pkg_name: contains executable .js/.mjs/.cjs files"
        MEDIUM_COUNT=$((MEDIUM_COUNT + 1))
        findings=$((findings + 1))
    fi

    stage3_found=$((stage3_found + findings))
}

# Find node_modules/@types directories
while IFS= read -r nm_dir; do
    [[ -z "$nm_dir" ]] && continue

    types_base="$nm_dir/@types"
    if [[ ! -d "$types_base" ]]; then
        continue
    fi

    if [[ "$DEEP_MODE" == true ]]; then
        # Deep: check ALL @types packages
        while IFS= read -r types_pkg; do
            [[ -z "$types_pkg" ]] && continue
            check_types_package "$types_pkg"
        done < <(find "$types_base" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
    else
        # Default: check only packages in devDependencies
        local_pkg_json="$(dirname "$nm_dir")/package.json"
        if [[ -f "$local_pkg_json" ]]; then
            dev_types=$(jq -r '.devDependencies // {} | keys[] | select(startswith("@types/")) | sub("@types/";"")' "$local_pkg_json" 2>/dev/null)
            while IFS= read -r type_name; do
                [[ -z "$type_name" ]] && continue
                # Handle scoped types (e.g., @types/babel__core -> babel__core)
                if [[ -d "$types_base/$type_name" ]]; then
                    check_types_package "$types_base/$type_name"
                fi
            done <<< "$dev_types"
        fi
    fi

done < <(find "$SCAN_DIR" -maxdepth 3 -type d -name "node_modules" \
    ! -path "*/node_modules/*/node_modules" \
    ! -path "*/.git/*" \
    2>/dev/null)

TYPES_FINDINGS=$stage3_found

if [[ $stage3_found -eq 0 ]]; then
    log "  ${GREEN}+${NC} No suspicious @types packages found"
fi
log ""

# ── Stage 4/5: package.json Scripts Audit ─────────────────────

log "──────────────────────────────────────────────────────────────────"
log "  Stage 4/5: package.json Scripts Audit"
log "──────────────────────────────────────────────────────────────────"
log ""

stage4_found=0

while IFS= read -r pkg_json; do
    [[ -z "$pkg_json" ]] && continue

    pkg_rel="${pkg_json#"$SCAN_DIR"/}"
    file_findings=0

    # Extract all script values as newline-separated text
    scripts_text=$(jq -r '.scripts // {} | to_entries[] | "\(.key)=\(.value)"' "$pkg_json" 2>/dev/null)

    if [[ -z "$scripts_text" ]]; then
        log "  ${GREEN}+${NC} $pkg_rel: no scripts"
        continue
    fi

    # HIGH: network tools in scripts
    if echo "$scripts_text" | grep -qE '\bcurl\b|\bwget\b|\bnc\b'; then
        local_match=$(echo "$scripts_text" | grep -E '\bcurl\b|\bwget\b|\bnc\b' | head -1)
        log "  ${RED}[HIGH]${NC} $pkg_rel: network tool in script (${local_match%%=*})"
        HIGH_COUNT=$((HIGH_COUNT + 1))
        file_findings=$((file_findings + 1))
    fi

    # HIGH: eval / node -e with encoded content
    if echo "$scripts_text" | grep -qE '\beval\b|node\s+-e\s'; then
        log "  ${RED}[HIGH]${NC} $pkg_rel: eval or node -e in scripts"
        HIGH_COUNT=$((HIGH_COUNT + 1))
        file_findings=$((file_findings + 1))
    fi

    # HIGH: encoded strings
    if echo "$scripts_text" | grep -qE '\\x[0-9a-fA-F]{2}|\\u\{|atob\(|Buffer\.from.*base64'; then
        log "  ${RED}[HIGH]${NC} $pkg_rel: encoded string in scripts"
        HIGH_COUNT=$((HIGH_COUNT + 1))
        file_findings=$((file_findings + 1))
    fi

    # MEDIUM: npx calling unknown packages inside scripts
    if echo "$scripts_text" | grep -qE '\bnpx\s+[a-z@]'; then
        npx_pkg=$(echo "$scripts_text" | grep -oE 'npx\s+[a-zA-Z@][a-zA-Z0-9@/_-]*' | head -1)
        log "  ${YELLOW}[MEDIUM]${NC} $pkg_rel: npx execution in scripts ($npx_pkg)"
        MEDIUM_COUNT=$((MEDIUM_COUNT + 1))
        file_findings=$((file_findings + 1))
    fi

    if [[ $file_findings -eq 0 ]]; then
        log "  ${GREEN}+${NC} $pkg_rel: scripts clean"
    fi

    stage4_found=$((stage4_found + file_findings))

done < <(find "$SCAN_DIR" -maxdepth 3 -type f -name "package.json" \
    ! -path "*/node_modules/*" \
    ! -path "*/.git/*" \
    2>/dev/null)

SCRIPT_FINDINGS=$stage4_found
log ""

# ── Stage 5/5: .d.ts Executable Code Detection ────────────────

log "──────────────────────────────────────────────────────────────────"
log "  Stage 5/5: .d.ts Executable Code Detection"
log "──────────────────────────────────────────────────────────────────"
log ""

stage5_found=0

# Collect .d.ts files from node_modules
dts_tmpfile=$(mktemp)

find "$SCAN_DIR" -path "*/node_modules/*.d.ts" -type f \
    ! -path "*/.git/*" \
    2>/dev/null > "$dts_tmpfile"

total_dts=$(wc -l < "$dts_tmpfile")

if [[ "$DEEP_MODE" == true ]]; then
    log "  ${BLUE}i${NC} Deep mode: checking all $total_dts .d.ts files"
    scan_dts="$dts_tmpfile"
else
    # Sample first 200
    sample_file=$(mktemp)
    head -200 "$dts_tmpfile" > "$sample_file"
    sample_count=$(wc -l < "$sample_file")
    log "  ${BLUE}i${NC} Default mode: sampling $sample_count of $total_dts .d.ts files"
    scan_dts="$sample_file"
fi

while IFS= read -r dts_file; do
    [[ -z "$dts_file" ]] && continue

    dts_rel="${dts_file#"$SCAN_DIR"/}"

    # Skip lines that are clearly type declarations and grep for executable code
    # We use a two-pass approach: grep for suspicious patterns, then filter out type decls

    # HIGH: require( without preceding "declare"
    if grep -nE '\brequire\s*\(' "$dts_file" 2>/dev/null | grep -vE '^\s*[0-9]+:\s*(declare|interface|type |export type|//|\*)' | grep -q .; then
        log "  ${RED}[HIGH]${NC} $dts_rel: require() call in .d.ts"
        HIGH_COUNT=$((HIGH_COUNT + 1))
        stage5_found=$((stage5_found + 1))
        continue
    fi

    # HIGH: dynamic import — exclude type-level import() which is common in .d.ts
    # e.g. typeof import("./foo").Bar, import("http").Server, Promise<import("x").Y>
    if grep -nE '\bimport\s*\(' "$dts_file" 2>/dev/null | grep -vE 'import\s+type|typeof\s+import\(|^\s*[0-9]+:\s*(declare|interface|type |export type|export \{|//|\*)|\)\s*\.\s*[A-Z]|<\s*import\(|:\s*import\(' | grep -q .; then
        log "  ${RED}[HIGH]${NC} $dts_rel: dynamic import() in .d.ts"
        HIGH_COUNT=$((HIGH_COUNT + 1))
        stage5_found=$((stage5_found + 1))
        continue
    fi

    # HIGH: eval, Function, exec
    if grep -nE '\beval\s*\(|\bFunction\s*\(|\bexec\s*\(' "$dts_file" 2>/dev/null | grep -vE '^\s*[0-9]+:\s*(declare|interface|type |export type|//|\*)' | grep -q .; then
        log "  ${RED}[HIGH]${NC} $dts_rel: eval/Function/exec in .d.ts"
        HIGH_COUNT=$((HIGH_COUNT + 1))
        stage5_found=$((stage5_found + 1))
        continue
    fi

    # HIGH: direct module usage (fs., child_process, http., net.)
    # Exclude type-level references: type annotations, function signatures, declare, interface, etc.
    if grep -nE '\bfs\.\b|\bchild_process\b|\bhttp\.\b|\bnet\.\b' "$dts_file" 2>/dev/null | grep -vE '^\s*[0-9]+:\s*(declare|interface|type |export (type|default function|function|declare)|//|\*|import|/// <reference)|\bimport\(|: typeof|:\s*(http|fs|net|child_process)\.' | grep -q .; then
        log "  ${RED}[HIGH]${NC} $dts_rel: direct module usage (fs/child_process/http/net) in .d.ts"
        HIGH_COUNT=$((HIGH_COUNT + 1))
        stage5_found=$((stage5_found + 1))
        continue
    fi

done < "$scan_dts"

# Cleanup temp files
rm -f "$dts_tmpfile"
[[ -v sample_file ]] && rm -f "$sample_file" 2>/dev/null

DTS_FINDINGS=$stage5_found

if [[ $stage5_found -eq 0 ]]; then
    log "  ${GREEN}+${NC} No executable code found in .d.ts files"
fi
log ""

# ── Summary ───────────────────────────────────────────────────

TOTAL_FINDINGS=$((TSCONFIG_FINDINGS + BUILD_CONFIG_FINDINGS + TYPES_FINDINGS + SCRIPT_FINDINGS + DTS_FINDINGS))

log "=================================================================="
log "  SUMMARY"
log "=================================================================="
log "  Projects scanned:       $TOTAL_PROJECTS"
log "  tsconfig findings:      $TSCONFIG_FINDINGS"
log "  Build config findings:  $BUILD_CONFIG_FINDINGS"
log "  @types findings:        $TYPES_FINDINGS"
log "  Script findings:        $SCRIPT_FINDINGS"
log "  .d.ts findings:         $DTS_FINDINGS"
log "  ──────────────────────"
log "  Total findings:         $TOTAL_FINDINGS ($HIGH_COUNT high, $MEDIUM_COUNT medium, $LOW_COUNT low)"
log ""
log "  Log: $LOG_FILE"
log ""

if [[ $HIGH_COUNT -gt 0 ]]; then
    log "  ${RED}ACTION REQUIRED:${NC} High-severity findings detected."
    log "  Review findings above — these may indicate supply chain compromise."
    log ""
    exit 2
elif [[ $TOTAL_FINDINGS -gt 0 ]]; then
    log "  ${YELLOW}Review findings above.${NC}"
    log ""
    exit 1
else
    log "  ${GREEN}No threat indicators found.${NC}"
    log ""
    exit 0
fi
