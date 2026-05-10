#!/usr/bin/env bats
# Snapshot tests: diff generated devcontainer.json against committed snapshots.
# A failing snapshot test means the merged output drifted — review the diff
# and either fix the regression or run `UPDATE_SNAPSHOTS=1 bats tests/dev/`
# to accept the new shape.

load 'test_helper'

setup() {
  PROJECT="$BATS_TEST_TMPDIR/proj"
}

@test "snapshot: python+fastapi" {
  run "$DEV_BIN" create snap --python --fastapi --in "$PROJECT"
  assert_success
  assert_snapshot_json "$PROJECT/.devcontainer/devcontainer.json" "python-fastapi.json"
}

@test "snapshot: python+notebooks+pytorch" {
  run "$DEV_BIN" create snap --python --notebooks --pytorch --in "$PROJECT"
  assert_success
  assert_snapshot_json "$PROJECT/.devcontainer/devcontainer.json" "python-notebooks-pytorch.json"
}

@test "snapshot: node+vite-ts" {
  run "$DEV_BIN" create snap --node --vite-ts --in "$PROJECT"
  assert_success
  assert_snapshot_json "$PROJECT/.devcontainer/devcontainer.json" "node-vite-ts.json"
}

@test "snapshot: cpp" {
  run "$DEV_BIN" create snap --cpp --in "$PROJECT"
  assert_success
  assert_snapshot_json "$PROJECT/.devcontainer/devcontainer.json" "cpp.json"
}

@test "snapshot: rust" {
  run "$DEV_BIN" create snap --rust --in "$PROJECT"
  assert_success
  assert_snapshot_json "$PROJECT/.devcontainer/devcontainer.json" "rust.json"
}
