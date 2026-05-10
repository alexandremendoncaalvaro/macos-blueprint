#!/usr/bin/env bash
set -euo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

if [ ! -f "package.json" ]; then
  echo "[post-create:astro] scaffolding astro"
  pnpm create astro@latest . --template minimal --no-install --no-git --yes 2>/dev/null || \
    npm create astro@latest . -- --template minimal --no-install --no-git --yes 2>/dev/null || true
fi

if [ -f "package.json" ] && [ ! -d "node_modules" ]; then
  pnpm install 2>/dev/null || npm install
fi
