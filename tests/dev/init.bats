#!/usr/bin/env bats
# `mac dev init` — devcontainer scaffolding for an existing project.

load 'test_helper'

setup() {
  PROJECT="$BATS_TEST_TMPDIR/My Existing Project"
  mkdir -p "$PROJECT"
}

@test "init infers project name from --in basename and sanitizes it" {
  run "$DEV_BIN" init --python --in "$PROJECT"
  assert_success
  assert_file_exists "$PROJECT/.devcontainer/devcontainer.json"
  assert_jq "$PROJECT/.devcontainer/devcontainer.json" '.name == "my-existing-project"'
}

@test "init respects explicit --name" {
  run "$DEV_BIN" init --python --in "$PROJECT" --name api
  assert_success
  assert_jq "$PROJECT/.devcontainer/devcontainer.json" '.name == "api"'
}

@test "init refuses unknown target dir" {
  run "$DEV_BIN" init --python --in "$BATS_TEST_TMPDIR/does-not-exist"
  assert_failure
  assert_output_contains "target dir does not exist"
}

@test "init does not clobber existing devcontainer without --force" {
  "$DEV_BIN" init --python --in "$PROJECT" >/dev/null
  run "$DEV_BIN" init --node --in "$PROJECT"
  assert_failure
  assert_output_contains "already exists"
}

@test "init --force overwrites existing devcontainer" {
  "$DEV_BIN" init --python --in "$PROJECT" >/dev/null
  run "$DEV_BIN" init --node --in "$PROJECT" --force
  assert_success
  assert_jq "$PROJECT/.devcontainer/devcontainer.json" '.image | contains("javascript-node")'
}
