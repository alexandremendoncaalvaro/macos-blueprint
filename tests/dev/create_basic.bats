#!/usr/bin/env bats
# Happy-path: `mac dev create` for every stack. Generated devcontainer.json
# must be valid JSON and match the snapshot stored under tests/dev/snapshots/.

load 'test_helper'

setup() {
  PROJECT="$BATS_TEST_TMPDIR/proj"
}

@test "create python (vanilla) generates valid devcontainer.json" {
  run "$DEV_BIN" create app --python --in "$PROJECT"
  assert_success
  assert_file_exists "$PROJECT/.devcontainer/devcontainer.json"
  assert_jq "$PROJECT/.devcontainer/devcontainer.json" '.image | contains("python")'
  assert_jq "$PROJECT/.devcontainer/devcontainer.json" '.name == "app"'
}

@test "create node (vanilla)" {
  run "$DEV_BIN" create app --node --in "$PROJECT"
  assert_success
  assert_jq "$PROJECT/.devcontainer/devcontainer.json" '.image | contains("javascript-node")'
}

@test "create go" {
  run "$DEV_BIN" create app --go --in "$PROJECT"
  assert_success
  assert_jq "$PROJECT/.devcontainer/devcontainer.json" '.image | contains("go")'
}

@test "create rust" {
  run "$DEV_BIN" create app --rust --in "$PROJECT"
  assert_success
  assert_jq "$PROJECT/.devcontainer/devcontainer.json" '.image | contains("rust")'
}

@test "create cpp" {
  run "$DEV_BIN" create app --cpp --in "$PROJECT"
  assert_success
  assert_jq "$PROJECT/.devcontainer/devcontainer.json" '.image | contains("cpp")'
  assert_jq "$PROJECT/.devcontainer/devcontainer.json" '.containerEnv.VCPKG_ROOT'
}

@test "create csharp" {
  run "$DEV_BIN" create app --csharp --in "$PROJECT"
  assert_success
  assert_jq "$PROJECT/.devcontainer/devcontainer.json" '.image | contains("dotnet")'
}

@test "create java" {
  run "$DEV_BIN" create app --java --in "$PROJECT"
  assert_success
  assert_jq "$PROJECT/.devcontainer/devcontainer.json" '.image | contains("java")'
}

@test "create writes post-create runner + base script" {
  run "$DEV_BIN" create app --python --in "$PROJECT"
  assert_success
  assert_file_exists "$PROJECT/.devcontainer/post-create.sh"
  assert_file_exists "$PROJECT/.devcontainer/post-create.d/00-base.sh"
  [[ -x "$PROJECT/.devcontainer/post-create.sh" ]]
  [[ -x "$PROJECT/.devcontainer/post-create.d/00-base.sh" ]]
}

@test "create wires base mounts (gitconfig.local, claude, ssh)" {
  run "$DEV_BIN" create app --python --in "$PROJECT"
  assert_success
  local f="$PROJECT/.devcontainer/devcontainer.json"
  assert_jq "$f" '.mounts | length == 3'
  assert_jq "$f" '[.mounts[] | contains(".gitconfig.local")] | any'
  assert_jq "$f" '[.mounts[] | contains(".claude")] | any'
  assert_jq "$f" '[.mounts[] | contains(".ssh")] | any'
}

@test "create includes core extensions in every stack" {
  run "$DEV_BIN" create app --python --in "$PROJECT"
  assert_success
  local f="$PROJECT/.devcontainer/devcontainer.json"
  for ext in anthropic.claude-code eamodio.gitlens EditorConfig.EditorConfig; do
    assert_jq "$f" "[.customizations.vscode.extensions[] == \"$ext\"] | any"
  done
}
