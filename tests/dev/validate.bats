#!/usr/bin/env bats
# `mac dev validate` — static checks on a generated .devcontainer.

load 'test_helper'

setup() {
  PROJECT="$BATS_TEST_TMPDIR/proj"
}

@test "validate fails on missing devcontainer" {
  mkdir -p "$PROJECT"
  run "$DEV_BIN" validate "$PROJECT"
  assert_failure
  assert_output_contains "no devcontainer.json"
}

@test "validate passes on freshly generated project" {
  "$DEV_BIN" create app --python --in "$PROJECT" >/dev/null
  run "$DEV_BIN" validate "$PROJECT"
  assert_success
  assert_output_contains "JSON parse"
  assert_output_contains "validate passed"
}

@test "validate flags missing name field" {
  "$DEV_BIN" create app --python --in "$PROJECT" >/dev/null
  jq 'del(.name)' "$PROJECT/.devcontainer/devcontainer.json" \
    > "$PROJECT/.devcontainer/devcontainer.json.tmp"
  mv "$PROJECT/.devcontainer/devcontainer.json.tmp" \
     "$PROJECT/.devcontainer/devcontainer.json"
  run "$DEV_BIN" validate "$PROJECT"
  assert_failure
  assert_output_contains "missing 'name'"
}

@test "validate flags missing image and build" {
  "$DEV_BIN" create app --python --in "$PROJECT" >/dev/null
  jq 'del(.image)' "$PROJECT/.devcontainer/devcontainer.json" \
    > "$PROJECT/.devcontainer/devcontainer.json.tmp"
  mv "$PROJECT/.devcontainer/devcontainer.json.tmp" \
     "$PROJECT/.devcontainer/devcontainer.json"
  run "$DEV_BIN" validate "$PROJECT"
  assert_failure
  assert_output_contains "missing both 'image' and 'build.dockerfile'"
}

@test "validate flags forwardPorts as wrong type" {
  "$DEV_BIN" create app --python --in "$PROJECT" >/dev/null
  jq '.forwardPorts = "8000"' "$PROJECT/.devcontainer/devcontainer.json" \
    > "$PROJECT/.devcontainer/devcontainer.json.tmp"
  mv "$PROJECT/.devcontainer/devcontainer.json.tmp" \
     "$PROJECT/.devcontainer/devcontainer.json"
  run "$DEV_BIN" validate "$PROJECT"
  assert_failure
  assert_output_contains "forwardPorts must be an array of integers"
}

@test "validate flags non-string in extensions array" {
  "$DEV_BIN" create app --python --in "$PROJECT" >/dev/null
  jq '.customizations.vscode.extensions += [42]' \
    "$PROJECT/.devcontainer/devcontainer.json" \
    > "$PROJECT/.devcontainer/devcontainer.json.tmp"
  mv "$PROJECT/.devcontainer/devcontainer.json.tmp" \
     "$PROJECT/.devcontainer/devcontainer.json"
  run "$DEV_BIN" validate "$PROJECT"
  assert_failure
  assert_output_contains "extensions must be an array of strings"
}

@test "validate flags features as wrong type" {
  "$DEV_BIN" create app --python --in "$PROJECT" >/dev/null
  jq '.features = ["str-instead-of-obj"]' \
    "$PROJECT/.devcontainer/devcontainer.json" \
    > "$PROJECT/.devcontainer/devcontainer.json.tmp"
  mv "$PROJECT/.devcontainer/devcontainer.json.tmp" \
     "$PROJECT/.devcontainer/devcontainer.json"
  run "$DEV_BIN" validate "$PROJECT"
  assert_failure
  assert_output_contains "features must be an object"
}

@test "validate parses JSONC files" {
  "$DEV_BIN" create app --python --in "$PROJECT" >/dev/null
  printf '// header comment\n%s' \
    "$(cat "$PROJECT/.devcontainer/devcontainer.json")" \
    > "$PROJECT/.devcontainer/devcontainer.json.tmp"
  mv "$PROJECT/.devcontainer/devcontainer.json.tmp" \
     "$PROJECT/.devcontainer/devcontainer.json"
  run "$DEV_BIN" validate "$PROJECT"
  assert_success
}
