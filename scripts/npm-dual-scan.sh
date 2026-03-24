# npm-dual-scan.sh — Dual-scanner wrapper for npm
# Routes install commands through both Socket Firewall (dry-run) and Aikido Safe Chain (real install).
# Non-install commands pass through Socket (or Aikido/bare npm as fallback).
# Source this file from ~/.bashrc AFTER safe-chain init.

npm() {
  local cmd="${1:-}"

  case "$cmd" in
    install|i|ci|add)
      if command -v sfw &>/dev/null && command -v aikido-npm &>/dev/null; then
        # Both available: Socket dry-run scan, then Aikido real install
        sfw npm "$@" --dry-run
        aikido-npm "$@"
      elif command -v sfw &>/dev/null; then
        # Socket only: real install through Socket (no dry-run needed)
        sfw npm "$@"
      elif command -v aikido-npm &>/dev/null; then
        # Aikido only: real install through Aikido
        aikido-npm "$@"
      else
        command npm "$@"
      fi
      ;;
    *)
      # Non-install commands: route through Socket if available
      if command -v sfw &>/dev/null; then
        sfw npm "$@"
      elif command -v aikido-npm &>/dev/null; then
        aikido-npm "$@"
      else
        command npm "$@"
      fi
      ;;
  esac
}
