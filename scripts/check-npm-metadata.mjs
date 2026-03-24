#!/usr/bin/env node
// check-npm-metadata — npm registry supply chain metadata checker
// Cross-references packages in package-lock.json against the npm registry
// to flag suspicious metadata patterns that may indicate compromised or
// malicious packages:
//
//   - Registry lookup failure (pulled/unpublished package)
//   - Typosquatting via Levenshtein distance from popular npm packages
//   - Recently published versions (< 7 days old)
//   - Missing repository URL
//   - Few releases (< 3 versions)
//   - No maintainer info
//   - Suspicious @types/ packages
//
// Usage:
//   node check-npm-metadata.mjs --lockfile package-lock.json
//   node check-npm-metadata.mjs --dir ./my-project
//   node check-npm-metadata.mjs --dir ./my-project --json
//   node check-npm-metadata.mjs --dir . --skip-types
//
// Exit codes:
//   0 = clean (no findings or LOW only)
//   1 = MEDIUM findings only
//   2 = any HIGH findings

import { readFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { parseArgs } from "node:util";
import https from "node:https";

// --- CLI ---

const { values } = parseArgs({
  options: {
    lockfile: { type: "string" },
    dir: { type: "string", default: "." },
    json: { type: "boolean", default: false },
    "skip-types": { type: "boolean", default: false },
  },
});

// --- Configuration ---

const RECENT_DAYS_THRESHOLD = 7;
const MIN_RELEASES_ESTABLISHED = 3;
const RATE_LIMIT_MS = 50;

const POPULAR_PACKAGES = new Set([
  "express", "react", "next", "vue", "lodash",
  "axios", "moment", "webpack", "babel-core", "typescript",
  "eslint", "prettier", "jest", "mocha", "chalk",
  "commander", "yargs", "inquirer", "ora", "fs-extra",
  "glob", "rimraf", "mkdirp", "dotenv", "cors",
  "body-parser", "cookie-parser", "passport", "jsonwebtoken", "mongoose",
  "sequelize", "prisma", "socket.io", "ws", "fastify",
  "koa", "tailwindcss", "postcss", "sass", "styled-components",
  "redux", "mobx", "zustand", "vite", "esbuild",
  "rollup", "uuid", "debug", "semver", "minimist",
]);

// --- Colors ---

const RED = "\x1b[0;31m";
const GREEN = "\x1b[0;32m";
const YELLOW = "\x1b[1;33m";
const BLUE = "\x1b[0;34m";
const BOLD = "\x1b[1m";
const NC = "\x1b[0m";

// --- Helpers ---

function logFinding(severity, pkg, message) {
  const color = severity === "HIGH" ? RED : severity === "MEDIUM" ? YELLOW : BLUE;
  process.stderr.write(`  ${color}[${severity}]${NC} ${BOLD}${pkg}${NC}: ${message}\n`);
}

function sleep(ms) {
  return new Promise(r => setTimeout(r, ms));
}

function fetchJSON(url) {
  return new Promise((resolve, reject) => {
    const req = https.get(url, {
      headers: { "User-Agent": "npm-security-tooling/0.1 (supply chain checker)" },
      timeout: 10000,
    }, (res) => {
      if (res.statusCode === 404) { resolve(null); return; }
      if (res.statusCode < 200 || res.statusCode >= 300) {
        reject(new Error(`HTTP ${res.statusCode}`));
        res.resume();
        return;
      }
      const chunks = [];
      res.on("data", (d) => chunks.push(d));
      res.on("end", () => {
        try { resolve(JSON.parse(Buffer.concat(chunks).toString())); }
        catch (e) { reject(e); }
      });
    });
    req.on("error", reject);
    req.on("timeout", () => { req.destroy(); reject(new Error("timeout")); });
  });
}

function editDistance(a, b) {
  if (a.length < b.length) return editDistance(b, a);
  if (b.length === 0) return a.length;
  let prev = Array.from({ length: b.length + 1 }, (_, i) => i);
  for (let i = 0; i < a.length; i++) {
    const curr = [i + 1];
    for (let j = 0; j < b.length; j++) {
      const cost = a[i] === b[j] ? 0 : 1;
      curr.push(Math.min(curr[j] + 1, prev[j + 1] + 1, prev[j] + cost));
    }
    prev = curr;
  }
  return prev[b.length];
}

function checkTyposquatting(packageName) {
  const name = packageName.toLowerCase().replace(/-/g, "").replace(/_/g, "");
  for (const popular of POPULAR_PACKAGES) {
    const pop = popular.toLowerCase().replace(/-/g, "").replace(/_/g, "");
    if (name === pop) continue; // exact match = it IS the popular package

    // Levenshtein distance
    if (editDistance(name, pop) <= 1 && name.length >= 3) {
      return popular;
    }
    // Common typosquatting suffixes/prefixes
    if (name === pop + "s" || name === pop + "2" || name === pop + "3" || name === pop + "js") {
      return popular;
    }
    if (name === "js" + pop || name === "node" + pop) {
      return popular;
    }
  }
  return null;
}

// --- Lockfile parsing ---

// Resolve npm aliases by comparing the lockfile key to the resolved tarball URL.
// e.g., key "@babel/traverse--for-generate-function-map" with resolved URL
// "https://registry.npmjs.org/@babel/traverse/-/traverse-7.28.6.tgz"
// means the real package is "@babel/traverse", not the aliased name.
function resolveAliasFromUrl(aliasName, resolvedUrl) {
  if (!resolvedUrl || !resolvedUrl.includes("registry.npmjs.org")) return null;
  // Extract package name from registry URL: .../pkgname/-/tarball-version.tgz
  // Scoped: .../(@scope%2fpkg or @scope/pkg)/-/pkg-version.tgz
  const match = resolvedUrl.match(
    /registry\.npmjs\.org\/(.+?)\/-\//
  );
  if (!match) return null;
  const realName = decodeURIComponent(match[1]);
  // Only return if the real name differs from the alias
  if (realName !== aliasName) return realName;
  return null;
}

function readLockfile(lockfilePath) {
  const raw = readFileSync(lockfilePath, "utf-8");
  const lock = JSON.parse(raw);
  const packages = {};

  if (lock.packages && (lock.lockfileVersion === 2 || lock.lockfileVersion === 3)) {
    // lockfileVersion 2/3: packages keyed as "node_modules/<name>"
    for (const [key, info] of Object.entries(lock.packages)) {
      if (!key || key === "") continue; // root entry
      let name = key.replace(/^node_modules\//, "");
      // Skip nested node_modules (transitive duplicates with different versions)
      if (name.includes("node_modules/")) continue;
      // Resolve npm aliases: if "resolved" URL points to a different package,
      // use the real package name. This handles cases like Metro bundler's
      // "@babel/traverse--for-generate-function-map": "npm:@babel/traverse@^7.25.0"
      if (info.resolved) {
        const realName = resolveAliasFromUrl(name, info.resolved);
        if (realName) name = realName;
      }
      packages[name] = info.version || "";
    }
  } else if (lock.dependencies) {
    // lockfileVersion 1 fallback
    for (const [name, info] of Object.entries(lock.dependencies)) {
      packages[name] = info.version || "";
    }
  }

  return packages;
}

// --- Registry checks ---

async function checkPackage(packageName, installedVersion, findings) {
  // Encode scoped package names for the registry URL (@ -> %40, / -> %2f)
  const encodedName = packageName.startsWith("@")
    ? `@${encodeURIComponent(packageName.slice(1))}`
    : encodeURIComponent(packageName);

  let data;
  try {
    data = await fetchJSON(`https://registry.npmjs.org/${encodedName}`);
  } catch {
    data = null;
  }

  if (data === null) {
    const severity = "HIGH";
    const message = installedVersion
      ? `Package (version ${installedVersion}) is in lockfile but NOT found on npm registry — may have been pulled/unpublished due to compromise. Investigate immediately`
      : "Package not found on npm registry — may be private or removed";
    findings.push({ package: packageName, version: installedVersion, severity, check: "not_on_registry", message });
    logFinding(severity, packageName, message);
    return;
  }

  const distTags = data["dist-tags"] || {};
  const latestVersion = distTags.latest || "";
  const timeMap = data.time || {};
  const versions = data.versions || {};
  const latestMeta = versions[latestVersion] || versions[installedVersion] || {};
  const maintainers = data.maintainers || [];

  // --- Check 1: Recently published version ---
  const versionToCheck = installedVersion || latestVersion;
  const publishedAt = timeMap[versionToCheck];
  if (publishedAt) {
    const pubDate = new Date(publishedAt);
    const ageDays = Math.floor((Date.now() - pubDate.getTime()) / (1000 * 60 * 60 * 24));
    if (ageDays <= RECENT_DAYS_THRESHOLD) {
      const msg = `Current version published ${ageDays} day(s) ago (${pubDate.toISOString().slice(0, 10)})`;
      findings.push({ package: packageName, version: versionToCheck, severity: "MEDIUM", check: "recent_release", message: msg });
      logFinding("MEDIUM", packageName, msg);
    }
  }

  // --- Check 2: Missing repository URL ---
  const repo = latestMeta.repository || data.repository;
  const hasRepo = repo && (typeof repo === "string" ? repo.length > 0 : Boolean(repo.url));
  if (!hasRepo) {
    const msg = "Missing repository URL";
    findings.push({ package: packageName, version: versionToCheck, severity: "LOW", check: "no_repository", message: msg });
    logFinding("LOW", packageName, msg);
  }

  // --- Check 3: Few releases ---
  const releaseCount = Object.keys(versions).length;
  if (releaseCount < MIN_RELEASES_ESTABLISHED) {
    const msg = `Only ${releaseCount} release(s) on npm — new or low-activity package`;
    findings.push({ package: packageName, version: versionToCheck, severity: "LOW", check: "few_releases", message: msg });
    logFinding("LOW", packageName, msg);
  }

  // --- Check 4: No maintainer info ---
  if (maintainers.length === 0) {
    const msg = "No maintainer information in package metadata";
    findings.push({ package: packageName, version: versionToCheck, severity: "LOW", check: "no_maintainer", message: msg });
    logFinding("LOW", packageName, msg);
  }

  // --- Check 5: Typosquatting ---
  const baseName = packageName.startsWith("@") ? null : packageName;
  if (baseName) {
    const similarTo = checkTyposquatting(baseName);
    if (similarTo) {
      const dist = editDistance(
        baseName.toLowerCase().replace(/-/g, "").replace(/_/g, ""),
        similarTo.toLowerCase().replace(/-/g, "").replace(/_/g, ""),
      );
      const msg = `Name suspiciously similar to popular package '${similarTo}' (edit distance: ${dist})`;
      findings.push({ package: packageName, version: versionToCheck, severity: "HIGH", check: "typosquatting", message: msg });
      logFinding("HIGH", packageName, msg);
    }
  }

  // --- Check 6: @types/ specific checks ---
  if (packageName.startsWith("@types/")) {
    const scripts = latestMeta.scripts || {};
    if (scripts.postinstall || scripts.preinstall || scripts.install) {
      const msg = "@types package has install scripts — highly suspicious for a type declaration package";
      findings.push({ package: packageName, version: versionToCheck, severity: "HIGH", check: "types_install_scripts", message: msg });
      logFinding("HIGH", packageName, msg);
    }

    // Check if @types package was very recently created
    const createdAt = timeMap.created;
    if (createdAt) {
      const createdDate = new Date(createdAt);
      const createdDaysAgo = Math.floor((Date.now() - createdDate.getTime()) / (1000 * 60 * 60 * 24));
      if (createdDaysAgo <= RECENT_DAYS_THRESHOLD) {
        const msg = `@types package was created only ${createdDaysAgo} day(s) ago — verify it is legitimate`;
        findings.push({ package: packageName, version: versionToCheck, severity: "MEDIUM", check: "types_recently_created", message: msg });
        logFinding("MEDIUM", packageName, msg);
      }
    }

    // Check downloads relative to base package
    const basePackage = packageName.slice("@types/".length);
    try {
      const typesDownloads = await fetchJSON(`https://api.npmjs.org/downloads/point/last-week/${encodedName}`);
      await sleep(RATE_LIMIT_MS);
      const baseEncodedName = encodeURIComponent(basePackage);
      const baseDownloads = await fetchJSON(`https://api.npmjs.org/downloads/point/last-week/${baseEncodedName}`);
      if (typesDownloads && baseDownloads && baseDownloads.downloads > 0) {
        const ratio = typesDownloads.downloads / baseDownloads.downloads;
        if (ratio < 0.001 && baseDownloads.downloads > 10000) {
          const msg = `@types package has very few downloads relative to base package '${basePackage}' (ratio: ${ratio.toFixed(5)})`;
          findings.push({ package: packageName, version: versionToCheck, severity: "MEDIUM", check: "types_low_downloads", message: msg });
          logFinding("MEDIUM", packageName, msg);
        }
      }
    } catch {
      // downloads API failure is non-fatal
    }
  }
}

// --- Main ---

async function main() {
  // Resolve lockfile path
  let lockfilePath;
  if (values.lockfile) {
    lockfilePath = resolve(values.lockfile);
  } else {
    lockfilePath = resolve(values.dir, "package-lock.json");
  }

  let packages;
  try {
    packages = readLockfile(lockfilePath);
  } catch (err) {
    process.stderr.write(`Error reading lockfile: ${lockfilePath}\n${err.message}\n`);
    process.exit(1);
  }

  const packageNames = Object.keys(packages);
  if (packageNames.length === 0) {
    process.stderr.write(`No packages found in ${lockfilePath}\n`);
    process.exit(0);
  }

  // Optionally skip @types/ packages
  const skipTypes = values["skip-types"];
  const toCheck = skipTypes
    ? packageNames.filter(n => !n.startsWith("@types/"))
    : packageNames;

  // Header
  process.stderr.write(`\n${"=".repeat(62)}\n`);
  process.stderr.write(`  ${BOLD}npm Supply Chain Metadata Check${NC}\n`);
  process.stderr.write(`${"=".repeat(62)}\n`);
  process.stderr.write(`  Source: ${BOLD}${lockfilePath}${NC}\n`);
  process.stderr.write(`  Packages: ${BOLD}${toCheck.length}${NC}\n`);
  process.stderr.write(`\n`);

  const allFindings = [];
  let checked = 0;
  let skippedErrors = 0;

  for (const name of toCheck.sort()) {
    try {
      await checkPackage(name, packages[name], allFindings);
      checked++;
    } catch {
      skippedErrors++;
    }
    await sleep(RATE_LIMIT_MS);
  }

  // Summary
  const high = allFindings.filter(f => f.severity === "HIGH").length;
  const medium = allFindings.filter(f => f.severity === "MEDIUM").length;
  const low = allFindings.filter(f => f.severity === "LOW").length;

  process.stderr.write(`\n${"=".repeat(62)}\n`);
  process.stderr.write(`  ${BOLD}SUMMARY${NC}\n`);
  process.stderr.write(`${"=".repeat(62)}\n`);
  process.stderr.write(`  Packages checked: ${BOLD}${checked}${NC}\n`);
  process.stderr.write(`  Skipped (errors):  ${BOLD}${skippedErrors}${NC}\n`);
  process.stderr.write(`  ${RED}HIGH:    ${high}${NC}\n`);
  process.stderr.write(`  ${YELLOW}MEDIUM:  ${medium}${NC}\n`);
  process.stderr.write(`  ${BLUE}LOW:     ${low}${NC}\n`);

  if (high > 0) {
    process.stderr.write(`\n  ${RED}${BOLD}ACTION REQUIRED:${NC} Review HIGH severity findings above.\n`);
  } else if (medium > 0) {
    process.stderr.write(`\n  ${YELLOW}Review MEDIUM severity findings.${NC}\n`);
  } else {
    process.stderr.write(`\n  ${GREEN}No significant supply chain risks detected.${NC}\n`);
  }
  process.stderr.write(`\n`);

  // JSON output to stdout
  if (values.json) {
    console.log(JSON.stringify(allFindings, null, 2));
  }

  // Exit code
  if (high > 0) process.exit(2);
  if (medium > 0) process.exit(1);
  process.exit(0);
}

main();
