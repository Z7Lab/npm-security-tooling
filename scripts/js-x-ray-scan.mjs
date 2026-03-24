#!/usr/bin/env node
// js-x-ray-scan — CLI wrapper for @nodesecure/js-x-ray
// Walks a project directory and runs static analysis on all JS/TS files
// Detects obfuscated code, encoded literals, unsafe imports, malicious patterns
//
// Usage:
//   node js-x-ray-scan.mjs --dir <path> [--json]
//
// Exit codes:
//   0 = clean (no warnings or info-only)
//   1 = warning-level findings
//   2 = critical-level findings

import { AstAnalyser } from "@nodesecure/js-x-ray";
import { readdir, stat } from "node:fs/promises";
import { join, extname, relative } from "node:path";
import { parseArgs } from "node:util";

const { values } = parseArgs({
  options: {
    dir: { type: "string", default: "." },
    json: { type: "boolean", default: false },
  },
});

const SCAN_EXTENSIONS = new Set([".js", ".jsx", ".ts", ".tsx", ".mjs", ".cjs"]);
const IGNORE_DIRS = new Set([
  "node_modules", "dist", "build", ".next", ".git",
  "coverage", ".cache", ".output", ".nuxt", "__pycache__",
]);
const MAX_FILE_SIZE = 500 * 1024; // 500KB — skip likely bundled/generated files

async function* walkDir(dir) {
  let entries;
  try {
    entries = await readdir(dir, { withFileTypes: true });
  } catch {
    return;
  }
  for (const entry of entries) {
    const fullPath = join(dir, entry.name);
    if (entry.isDirectory()) {
      if (!IGNORE_DIRS.has(entry.name) && !entry.name.startsWith(".")) {
        yield* walkDir(fullPath);
      }
    } else if (SCAN_EXTENSIONS.has(extname(entry.name)) && !entry.name.endsWith(".min.js")) {
      try {
        const fileInfo = await stat(fullPath);
        if (fileInfo.size <= MAX_FILE_SIZE) {
          yield fullPath;
        }
      } catch {
        // skip unreadable files
      }
    }
  }
}

const scanner = new AstAnalyser();
const allWarnings = [];
let filesScanned = 0;
let filesErrored = 0;

for await (const filePath of walkDir(values.dir)) {
  filesScanned++;
  try {
    const result = await scanner.analyseFile(filePath);
    if (result.warnings && result.warnings.length > 0) {
      for (const warning of result.warnings) {
        allWarnings.push({
          file: relative(values.dir, filePath),
          kind: warning.kind,
          severity: warning.severity || "Warning",
          value: warning.value || null,
          location: warning.location || null,
        });
      }
    }
  } catch {
    filesErrored++;
  }
}

if (values.json) {
  console.log(JSON.stringify({
    filesScanned,
    filesErrored,
    totalWarnings: allWarnings.length,
    warnings: allWarnings,
  }, null, 2));
} else {
  const bySeverity = { Critical: [], Warning: [], Information: [] };
  for (const w of allWarnings) {
    const bucket = bySeverity[w.severity] || bySeverity.Information;
    bucket.push(w);
  }

  console.log(`Files scanned: ${filesScanned}`);
  if (filesErrored > 0) {
    console.log(`Files skipped (parse errors): ${filesErrored}`);
  }
  console.log(`Findings: ${allWarnings.length} (${bySeverity.Critical.length} critical, ${bySeverity.Warning.length} warning, ${bySeverity.Information.length} info)`);

  if (allWarnings.length > 0) {
    console.log("");
    for (const w of [...bySeverity.Critical, ...bySeverity.Warning]) {
      const loc = w.location ? `:${w.location.start?.line || "?"}` : "";
      console.log(`  ${w.severity.toUpperCase().padEnd(8)} ${w.kind} in ${w.file}${loc}`);
      if (w.value) {
        const val = String(w.value).length > 80 ? String(w.value).slice(0, 80) + "..." : w.value;
        console.log(`           Value: ${val}`);
      }
    }
    if (bySeverity.Information.length > 0) {
      console.log(`  ... and ${bySeverity.Information.length} informational finding(s)`);
    }
  }
}

const hasCritical = allWarnings.some(w => w.severity === "Critical");
const hasWarning = allWarnings.some(w => w.severity === "Warning");
process.exit(hasCritical ? 2 : hasWarning ? 1 : 0);
