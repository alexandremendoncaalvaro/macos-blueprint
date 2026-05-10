#!/usr/bin/env bash
set -euo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

if [ ! -f "go.mod" ]; then
  module="$(basename "$PWD")"
  echo "[post-create:go] go mod init $module"
  go mod init "$module" 2>/dev/null || true
fi
