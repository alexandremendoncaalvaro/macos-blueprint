#!/usr/bin/env bash
set -euo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# OpenCV needs system libs for headless GUI/codec support.
if command -v sudo >/dev/null 2>&1; then
  sudo apt-get update -qq
  sudo apt-get install -y --no-install-recommends \
    libgl1 libglib2.0-0 libsm6 libxext6 libxrender1 libgomp1 ffmpeg >/dev/null
fi

if ! grep -q 'opencv-python' pyproject.toml 2>/dev/null; then
  echo "[post-create:opencv] uv add opencv-python numpy"
  uv add opencv-python numpy 2>/dev/null || true
fi
