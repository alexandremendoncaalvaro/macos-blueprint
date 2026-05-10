#!/usr/bin/env bats
# Edge cases: invalid input, unknown stacks/flavors, missing args.

load 'test_helper'

setup() {
  PROJECT="$BATS_TEST_TMPDIR/proj"
}

@test "create without name fails" {
  run "$DEV_BIN" create --python --in "$PROJECT"
  assert_failure
  assert_output_contains "name required"
}

@test "create without stack fails with hint" {
  run "$DEV_BIN" create app --in "$PROJECT"
  assert_failure
  assert_output_contains "stack required"
}

@test "create with unknown flavor for stack fails with available list" {
  run "$DEV_BIN" create app --python --rust-clippy --in "$PROJECT"
  assert_failure
  assert_output_contains "unknown flavor for python"
  assert_output_contains "fastapi"
}

@test "create handles --in with non-existent parent (mkdir -p)" {
  run "$DEV_BIN" create app --python --in "$BATS_TEST_TMPDIR/a/b/c/d"
  assert_success
  assert_file_exists "$BATS_TEST_TMPDIR/a/b/c/d/.devcontainer/devcontainer.json"
}

@test "create with no flavors still produces valid output" {
  run "$DEV_BIN" create app --rust --in "$PROJECT"
  assert_success
  assert_jq "$PROJECT/.devcontainer/devcontainer.json" '.name == "app"'
}

@test "stacks command lists all stacks" {
  run "$DEV_BIN" stacks
  assert_success
  for s in python node go rust cpp csharp java; do
    assert_output_contains "$s"
  done
}

@test "flavors command requires a stack argument" {
  run "$DEV_BIN" flavors
  assert_failure
}

@test "flavors python lists known flavors" {
  run "$DEV_BIN" flavors python
  assert_success
  for f in fastapi notebooks pytorch tensorflow; do
    assert_output_contains "$f"
  done
}
