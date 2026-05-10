#!/usr/bin/env bats
# `mac dev clean` — removes .devcontainer/ with confirmation.

load 'test_helper'

setup() {
  PROJECT="$BATS_TEST_TMPDIR/proj"
}

@test "clean --force removes .devcontainer" {
  "$DEV_BIN" create app --python --in "$PROJECT" >/dev/null
  run "$DEV_BIN" clean "$PROJECT" --force
  assert_success
  [ ! -d "$PROJECT/.devcontainer" ]
}

@test "clean is a no-op when nothing exists" {
  mkdir -p "$PROJECT"
  run "$DEV_BIN" clean "$PROJECT" --force
  assert_success
  assert_output_contains "nothing to clean"
}

@test "clean fails non-interactively without --force" {
  "$DEV_BIN" create app --python --in "$PROJECT" >/dev/null
  # bats `run` uses non-interactive stdin/stdout, so prompt path errors out.
  run "$DEV_BIN" clean "$PROJECT"
  assert_failure
  assert_output_contains "non-interactive"
}
