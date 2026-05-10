#!/usr/bin/env bash
# CPU TensorFlow build. For GPU on Linux hosts, swap to tensorflow[and-cuda].
set -euo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

if ! grep -q '"tensorflow"' pyproject.toml 2>/dev/null; then
  echo "[post-create:tensorflow] uv add tensorflow"
  uv add tensorflow 2>/dev/null || true
fi
