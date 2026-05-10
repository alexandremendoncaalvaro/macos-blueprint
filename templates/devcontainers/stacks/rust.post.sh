#!/usr/bin/env bash
set -euo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

if [ ! -f "Cargo.toml" ]; then
  echo "[post-create:rust] cargo init"
  cargo init --name "$(basename "$PWD")" 2>/dev/null || true
fi
