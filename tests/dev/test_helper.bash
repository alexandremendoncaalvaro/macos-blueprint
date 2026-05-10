# Shared helpers for `mac dev` test suite.
#
# bats sets these for free per @test:
#   $status         exit code of `run` command
#   $output         stdout+stderr (when using `run`)
#   $lines          $output split into array
#   $BATS_TEST_TMPDIR  unique tmpdir per test, auto-cleaned
#
# Conventions:
#   - DEV_BIN points at the script under test (NOT the user's installed copy)
#   - Tests must not depend on host state beyond standard Unix utilities + jq
#   - Snapshots live in tests/dev/snapshots/, regenerated via UPDATE_SNAPSHOTS=1

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEV_BIN="$DOTFILES/scripts/dev.sh"
TEMPLATES="$DOTFILES/templates/devcontainers"
SNAPSHOT_DIR="$DOTFILES/tests/dev/snapshots"

# ── Assertions ──────────────────────────────────────────────────────────────

assert_success() {
  if (( status != 0 )); then
    printf '✗ expected success, got exit=%d\n  output: %s\n' "$status" "$output" >&2
    return 1
  fi
}

assert_failure() {
  if (( status == 0 )); then
    printf '✗ expected failure, got exit=0\n  output: %s\n' "$output" >&2
    return 1
  fi
}

# Substring match against $output.
assert_output_contains() {
  if [[ "$output" != *"$1"* ]]; then
    printf '✗ expected output to contain: %s\n  actual: %s\n' "$1" "$output" >&2
    return 1
  fi
}

assert_file_exists() {
  if [[ ! -f "$1" ]]; then
    printf '✗ expected file to exist: %s\n' "$1" >&2
    return 1
  fi
}

assert_jq() {
  local file="$1" expr="$2"
  if ! jq -e "$expr" "$file" >/dev/null; then
    printf '✗ jq expression failed: %s\n  on: %s\n' "$expr" "$file" >&2
    jq . "$file" >&2 || true
    return 1
  fi
}

# Snapshot compare: writes $1 (file) against snapshots/$2; on UPDATE_SNAPSHOTS=1
# it overwrites the snapshot. Normalizes JSON via jq -S to ignore key order.
assert_snapshot_json() {
  local actual="$1" snap_name="$2"
  local snap="$SNAPSHOT_DIR/$snap_name"

  if [[ "${UPDATE_SNAPSHOTS:-0}" == "1" || ! -f "$snap" ]]; then
    jq -S . "$actual" > "$snap"
    echo "📸 snapshot written: $snap" >&2
    return 0
  fi

  if ! diff <(jq -S . "$actual") <(jq -S . "$snap") >/dev/null; then
    printf '✗ snapshot mismatch for %s\n' "$snap_name" >&2
    diff <(jq -S . "$snap") <(jq -S . "$actual") | head -40 >&2
    printf '   re-run with UPDATE_SNAPSHOTS=1 to overwrite\n' >&2
    return 1
  fi
}
