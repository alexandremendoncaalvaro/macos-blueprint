#!/usr/bin/env bash
# CPU-only PyTorch (devcontainers don't expose GPU on macOS host).
# For CUDA, override locally with:
#   uv add torch --index-url https://download.pytorch.org/whl/cu121
set -euo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

if ! grep -q '"torch"' pyproject.toml 2>/dev/null; then
  echo "[post-create:pytorch] uv add torch torchvision (CPU)"
  uv add torch torchvision --index-url https://download.pytorch.org/whl/cpu 2>/dev/null || true
fi
