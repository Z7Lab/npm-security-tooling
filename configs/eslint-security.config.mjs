// ESLint security-only configuration for SAST scanning
// Used by sast-scan.sh — does NOT interfere with project ESLint configs
//
// Requires: npm install -g eslint eslint-plugin-security eslint-plugin-no-unsanitized

import pluginSecurity from "eslint-plugin-security";
import pluginNoUnsanitized from "eslint-plugin-no-unsanitized";

export default [
  {
    files: ["**/*.js", "**/*.jsx", "**/*.ts", "**/*.tsx", "**/*.mjs", "**/*.cjs"],
    ignores: [
      "**/node_modules/**",
      "**/dist/**",
      "**/build/**",
      "**/.next/**",
      "**/coverage/**",
      "**/*.min.js",
      "**/*.bundle.js",
    ],
    plugins: {
      security: pluginSecurity,
      "no-unsanitized": pluginNoUnsanitized,
    },
    rules: {
      // eslint-plugin-security — all recommended rules
      ...pluginSecurity.configs.recommended.rules,

      // eslint-plugin-no-unsanitized — detect innerHTML, outerHTML, document.write
      "no-unsanitized/method": "warn",
      "no-unsanitized/property": "warn",

      // Upgrade critical rules from warn to error
      "security/detect-eval-with-expression": "error",
      "security/detect-child-process": "error",
      "security/detect-non-literal-require": "error",
      "security/detect-possible-timing-attacks": "warn",
    },
  },
];
