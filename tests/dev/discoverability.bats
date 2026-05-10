#!/usr/bin/env bats
# Help, stacks, flavors — surface area users hit before doing anything else.

load 'test_helper'

@test "no args prints usage" {
  run "$DEV_BIN"
  assert_success
  assert_output_contains "mac dev"
  assert_output_contains "create"
}

@test "--help prints usage" {
  run "$DEV_BIN" --help
  assert_success
  assert_output_contains "Stacks:"
}

@test "unknown subcommand fails with usage" {
  run "$DEV_BIN" frobnicate
  assert_failure
  assert_output_contains "unknown subcommand"
}

@test "every stack has a JSON template" {
  run "$DEV_BIN" stacks
  assert_success
  # Strip ANSI escapes from output before parsing.
  local clean
  clean="$(printf '%s' "$output" | sed $'s/\033\\[[0-9;]*m//g')"
  while IFS= read -r line; do
    local s="${line//[[:space:]]/}"
    [[ -z "$s" || "$s" == "Availablestacks:" ]] && continue
    [[ -f "$TEMPLATES/stacks/$s.json" ]] \
      || { echo "missing template: $s"; return 1; }
  done <<< "$clean"
}

@test "every python flavor has a JSON template" {
  run "$DEV_BIN" flavors python
  assert_success
  local clean
  clean="$(printf '%s' "$output" | sed $'s/\033\\[[0-9;]*m//g')"
  while IFS= read -r line; do
    local f="${line//[[:space:]]/}"
    [[ -z "$f" || "$f" == "Flavorsforpython:" ]] && continue
    [[ -f "$TEMPLATES/flavors/python-$f.json" ]] \
      || { echo "missing flavor: python-$f"; return 1; }
  done <<< "$clean"
}
