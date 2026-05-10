#!/usr/bin/env bats
# `mac dev list` — handles JSONC, finds devcontainers under HOME-rooted dirs.
# Note: list scans $HOME/Dev, $HOME/boostlingo, $HOME/Projetos by design.
# Tests therefore stub HOME and exercise that contract.

load 'test_helper'

setup() {
  FAKE_HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$FAKE_HOME/Dev/proj-a/.devcontainer"
  mkdir -p "$FAKE_HOME/Dev/proj-b/.devcontainer"
  cat > "$FAKE_HOME/Dev/proj-a/.devcontainer/devcontainer.json" <<'JSON'
{ "name": "alpha", "image": "python:3.13" }
JSON
  cat > "$FAKE_HOME/Dev/proj-b/.devcontainer/devcontainer.json" <<'JSON'
// jsonc with comments — must still parse
{ "name": "beta", "image": "node:22" }
JSON
}

@test "list reports projects under \$HOME/Dev" {
  HOME="$FAKE_HOME" run "$DEV_BIN" list
  assert_success
  assert_output_contains "alpha"
  assert_output_contains "beta"
}

@test "list parses JSONC files (line comments)" {
  HOME="$FAKE_HOME" run "$DEV_BIN" list
  assert_success
  # If the JSONC parser regressed, beta would render as "?" or "unnamed".
  assert_output_contains "beta"
}

@test "list under empty HOME prints 'none'" {
  HOME="$BATS_TEST_TMPDIR/empty-home" run "$DEV_BIN" list
  assert_success
  assert_output_contains "none"
}
