#!/usr/bin/env bash
# Runner: executes every script in .devcontainer/post-create.d/ in lexical order.
# Adding a flavor = drop a new NN-name.sh in that dir; no edits here required.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/post-create.d"

if [ ! -d "$DIR" ]; then
  echo "[post-create] no post-create.d dir, nothing to run"
  exit 0
fi

shopt -s nullglob
for script in "$DIR"/*.sh; do
  echo "[post-create] running $(basename "$script")"
  bash "$script"
done

echo "[post-create] all done"
