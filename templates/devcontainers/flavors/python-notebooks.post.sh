#!/usr/bin/env bash
set -euo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

if ! grep -q '"jupyter"' pyproject.toml 2>/dev/null; then
  echo "[post-create:notebooks] uv add jupyter ipykernel pandas matplotlib"
  uv add jupyter ipykernel pandas matplotlib 2>/dev/null || true
fi
