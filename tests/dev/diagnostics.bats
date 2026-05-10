#!/usr/bin/env bats
# Did-you-mean suggestions, multi-stack guard, invalid name rejection.

load 'test_helper'

setup() {
  PROJECT="$BATS_TEST_TMPDIR/proj"
}

@test "stack typo (--pytho) suggests --python" {
  run "$DEV_BIN" create app --pytho --in "$PROJECT"
  assert_failure
  assert_output_contains "did you mean --python"
}

@test "flavor typo (--fastpi) suggests --fastapi" {
  run "$DEV_BIN" create app --python --fastpi --in "$PROJECT"
  assert_failure
  assert_output_contains "did you mean --fastapi"
}

@test "two stacks specified rejects with explicit error" {
  run "$DEV_BIN" create app --python --node --in "$PROJECT"
  assert_failure
  assert_output_contains "multiple stacks"
}

@test "invalid project name with space is rejected" {
  run "$DEV_BIN" create "my app" --python --in "$PROJECT"
  assert_failure
  assert_output_contains "invalid project name"
}

@test "create without --force aborts when devcontainer already exists" {
  "$DEV_BIN" create app --python --in "$PROJECT" >/dev/null
  run "$DEV_BIN" create app --python --in "$PROJECT"
  assert_failure
  assert_output_contains "already exists"
}

@test "create --force overwrites existing devcontainer" {
  "$DEV_BIN" create app --python --in "$PROJECT" >/dev/null
  run "$DEV_BIN" create app --node --in "$PROJECT" --force
  assert_success
  assert_jq "$PROJECT/.devcontainer/devcontainer.json" '.image | contains("javascript-node")'
}
