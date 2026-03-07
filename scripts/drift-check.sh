#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# drift-check.sh — detect configuration drift from dotfiles
#
# Runs bootstrap --check and sends a macOS notification if drift is found.
# Designed to run weekly via launchd.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$HOME/.local/share/dotfiles"
LOG_FILE="$LOG_DIR/drift-check.log"
mkdir -p "$LOG_DIR"

# Homebrew must be on PATH for non-interactive shells.
eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || true)"

# Run bootstrap in check mode and capture output.
output=$("$DOTFILES/bootstrap.sh" --check 2>&1) || true

# Count warnings and errors (strip ANSI codes).
clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')
warnings=$(echo "$clean" | grep -c '  !  ' || true)
errors=$(echo "$clean" | grep -c '  ✗  ' || true)
total=$((warnings + errors))

# Log the result.
{
  echo "── $(date '+%Y-%m-%d %H:%M:%S') ──"
  echo "Warnings: $warnings | Errors: $errors"
  echo "$clean" | grep -E '  [!✗]  ' || true
  echo ""
} >> "$LOG_FILE"

# Trim log to last 500 lines.
if [[ $(wc -l < "$LOG_FILE") -gt 500 ]]; then
  tail -500 "$LOG_FILE" > "$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"
fi

# Notify if drift detected.
if [[ $total -gt 0 ]]; then
  osascript -e "display notification \"$total issue(s) found. Run ./bootstrap.sh to fix.\" with title \"dotfiles drift\" subtitle \"$warnings warning(s), $errors error(s)\""
fi

exit 0
