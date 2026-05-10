#!/usr/bin/env bash
set -euo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

if [ ! -f "package.json" ]; then
  echo "[post-create:vite-ts] scaffolding vite + react-ts"
  pnpm create vite . --template react-ts --yes 2>/dev/null || \
    npm create vite@latest . -- --template react-ts --yes 2>/dev/null || true
fi

if [ -f "package.json" ] && [ ! -d "node_modules" ]; then
  pnpm install 2>/dev/null || npm install
fi
