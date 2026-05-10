#!/usr/bin/env bash
set -euo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

if ! grep -q '"fastapi"' pyproject.toml 2>/dev/null; then
  echo "[post-create:fastapi] uv add fastapi[standard]"
  uv add 'fastapi[standard]' 2>/dev/null || true
fi

# Scaffold a starter app if none exists.
if [ ! -f "main.py" ] && [ ! -d "app" ]; then
  cat > main.py <<'PY'
from fastapi import FastAPI

app = FastAPI()


@app.get("/")
def root() -> dict[str, str]:
    return {"message": "ok"}
PY
  echo "[post-create:fastapi] wrote main.py"
fi
