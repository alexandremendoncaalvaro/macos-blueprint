#!/usr/bin/env bash
# Python stack post-create: ensure uv project initialized.
set -euo pipefail

cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

if [ ! -f "pyproject.toml" ]; then
  echo "[post-create:python] uv init"
  uv init --no-readme --no-pin-python || true
fi

if [ -f "pyproject.toml" ] && [ ! -d ".venv" ]; then
  echo "[post-create:python] uv sync"
  uv sync 2>/dev/null || uv venv 2>/dev/null || true
fi
