#!/usr/bin/env bash
# Base post-create: copy host SSH keys (read-only mount) into a writable
# location with correct permissions, install claude-code if missing.
set -euo pipefail

# SSH: copy from read-only mount so ssh can use it (needs 0600).
if [ -d "$HOME/.ssh-host" ]; then
  mkdir -p "$HOME/.ssh"
  cp -f "$HOME/.ssh-host"/* "$HOME/.ssh/" 2>/dev/null || true
  chmod 700 "$HOME/.ssh"
  chmod 600 "$HOME/.ssh"/* 2>/dev/null || true
  chmod 644 "$HOME/.ssh"/*.pub 2>/dev/null || true
fi

# claude-code CLI
if command -v npm >/dev/null 2>&1 && ! command -v claude >/dev/null 2>&1; then
  npm install -g @anthropic-ai/claude-code 2>/dev/null || true
fi

# starship init for sub-shells (idempotent)
if ! grep -q 'starship init' "$HOME/.zshrc" 2>/dev/null; then
  echo 'command -v starship >/dev/null 2>&1 && eval "$(starship init zsh)"' >> "$HOME/.zshrc"
fi

echo "[post-create:base] done"
