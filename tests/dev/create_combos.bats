#!/usr/bin/env bats
# Stack + flavor combinations: extension list, ports, post-create scripts.

load 'test_helper'

setup() {
  PROJECT="$BATS_TEST_TMPDIR/proj"
}

@test "python+fastapi adds port 8000" {
  run "$DEV_BIN" create api --python --fastapi --in "$PROJECT"
  assert_success
  assert_jq "$PROJECT/.devcontainer/devcontainer.json" '.forwardPorts == [8000]'
}

@test "python+fastapi adds rest-client extension" {
  run "$DEV_BIN" create api --python --fastapi --in "$PROJECT"
  assert_success
  assert_jq "$PROJECT/.devcontainer/devcontainer.json" \
    '[.customizations.vscode.extensions[] == "humao.rest-client"] | any'
}

@test "python+notebooks adds jupyter extensions" {
  run "$DEV_BIN" create nb --python --notebooks --in "$PROJECT"
  assert_success
  assert_jq "$PROJECT/.devcontainer/devcontainer.json" \
    '[.customizations.vscode.extensions[] == "ms-toolsai.jupyter"] | any'
}

@test "python+notebooks+pytorch combines extensions and post-create scripts" {
  run "$DEV_BIN" create ml --python --notebooks --pytorch --in "$PROJECT"
  assert_success
  assert_file_exists "$PROJECT/.devcontainer/post-create.d/10-python.sh"
  assert_file_exists "$PROJECT/.devcontainer/post-create.d/20-python-notebooks.sh"
  assert_file_exists "$PROJECT/.devcontainer/post-create.d/21-python-pytorch.sh"
}

@test "node+vite-ts forwards Vite port" {
  run "$DEV_BIN" create web --node --vite-ts --in "$PROJECT"
  assert_success
  assert_jq "$PROJECT/.devcontainer/devcontainer.json" '.forwardPorts == [5173]'
}

@test "node+astro forwards Astro port" {
  run "$DEV_BIN" create web --node --astro --in "$PROJECT"
  assert_success
  assert_jq "$PROJECT/.devcontainer/devcontainer.json" '.forwardPorts == [4321]'
}

@test "extensions array is deduped after layering" {
  run "$DEV_BIN" create m --python --fastapi --notebooks --in "$PROJECT"
  assert_success
  # Count duplicates in extensions array — must be zero.
  run jq '.customizations.vscode.extensions
          | group_by(.) | map(select(length>1)) | length' \
    "$PROJECT/.devcontainer/devcontainer.json"
  assert_success
  [ "$output" = "0" ]
}

@test "features object contains uv for python stack" {
  run "$DEV_BIN" create app --python --in "$PROJECT"
  assert_success
  assert_jq "$PROJECT/.devcontainer/devcontainer.json" \
    '.features | keys[] | select(contains("uv"))'
}
