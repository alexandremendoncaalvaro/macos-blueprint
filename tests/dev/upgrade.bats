#!/usr/bin/env bats
# `mac dev upgrade` + `mac dev diff` — round-trip via .mac-dev.json metadata.

load 'test_helper'

setup() {
  PROJECT="$BATS_TEST_TMPDIR/proj"
}

@test "create writes .mac-dev.json metadata" {
  run "$DEV_BIN" create app --python --fastapi --in "$PROJECT"
  assert_success
  assert_file_exists "$PROJECT/.devcontainer/.mac-dev.json"
  assert_jq "$PROJECT/.devcontainer/.mac-dev.json" '.stack == "python"'
  assert_jq "$PROJECT/.devcontainer/.mac-dev.json" '.flavors == ["fastapi"]'
}

@test "diff on freshly created project shows no changes" {
  "$DEV_BIN" create app --python --in "$PROJECT" >/dev/null
  run "$DEV_BIN" diff "$PROJECT"
  assert_success
  assert_output_contains "no changes"
}

@test "diff detects manual edits" {
  "$DEV_BIN" create app --python --in "$PROJECT" >/dev/null
  jq '.containerEnv.MANUAL_EDIT = "yes"' \
    "$PROJECT/.devcontainer/devcontainer.json" \
    > "$PROJECT/.devcontainer/devcontainer.json.tmp"
  mv "$PROJECT/.devcontainer/devcontainer.json.tmp" \
     "$PROJECT/.devcontainer/devcontainer.json"
  run "$DEV_BIN" diff "$PROJECT"
  assert_success
  assert_output_contains "MANUAL_EDIT"
}

@test "upgrade regenerates and discards manual edits" {
  "$DEV_BIN" create app --python --in "$PROJECT" >/dev/null
  jq '.containerEnv.MANUAL_EDIT = "yes"' \
    "$PROJECT/.devcontainer/devcontainer.json" \
    > "$PROJECT/.devcontainer/devcontainer.json.tmp"
  mv "$PROJECT/.devcontainer/devcontainer.json.tmp" \
     "$PROJECT/.devcontainer/devcontainer.json"
  run "$DEV_BIN" upgrade "$PROJECT"
  assert_success
  run jq -e '.containerEnv.MANUAL_EDIT // empty' \
    "$PROJECT/.devcontainer/devcontainer.json"
  assert_failure
}

@test "upgrade fails when metadata is missing" {
  "$DEV_BIN" create app --python --in "$PROJECT" >/dev/null
  rm "$PROJECT/.devcontainer/.mac-dev.json"
  run "$DEV_BIN" upgrade "$PROJECT"
  assert_failure
  assert_output_contains "no .devcontainer/.mac-dev.json"
}
