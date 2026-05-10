#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# mac dev — generate devcontainers from layered templates
#
# Templates live under ~/dotfiles/templates/devcontainers/:
#   _base/                 common config + post-create runner
#   stacks/<stack>.json    image + features + extensions for a language
#   flavors/<stack>-<f>.json   overlay (e.g. python-fastapi adds ports + libs)
#
# Layering strategy: jq built-in `*` does deep object merge but replaces
# arrays. Known-array fields (extensions, mounts, ports) are extracted
# from every layer, concatenated and de-duplicated, then re-injected.
#
# Each layer may also ship a sibling .post.sh — copied into
# .devcontainer/post-create.d/ and run inside the container after build.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATES="$DOTFILES/templates/devcontainers"

RED='\033[1;31m'; GREEN='\033[1;32m'; YELLOW='\033[1;33m'
BLUE='\033[1;34m'; GREY='\033[0;90m'; BOLD='\033[1m'; RESET='\033[0m'

ok()   { printf "${GREEN}  ✓${RESET}  %s\n" "$*"; }
fail() { printf "${RED}  ✗${RESET}  %s\n" "$*"; }
warn() { printf "${YELLOW}  !${RESET}  %s\n" "$*"; }
info() { printf "${BLUE}  ·${RESET}  %s\n" "$*"; }

usage() {
  cat <<EOF
${BOLD}mac dev${RESET} — devcontainer scaffolding

${BOLD}Usage:${RESET}
  mac dev create <name> --<stack> [--<flavor>...] [--in <path>] [--force]
  mac dev init --<stack> [--<flavor>...] [--name <n>] [--in <path>] [--force]
                                          Add devcontainer to current dir (existing project)
  mac dev list                            List devcontainers in ~/Dev, ~/boostlingo
  mac dev open [path]                     Open path in VS Code (prompts reopen)
  mac dev validate [path]                 Schema/shape + mounts + scripts + image checks
  mac dev diff [path]                     Show what 'upgrade' would change
  mac dev upgrade [path] [--force]        Regenerate devcontainer from saved metadata
  mac dev rebuild [path]                  devcontainer CLI rebuild + reopen
  mac dev clean [path] [--force]          Remove .devcontainer/ (with confirm)
  mac dev mount-claude                    Add ~/.claude bind mount to current project
  mac dev sync-ext                        Sync VSCode defaultExtensions with Brewfile
  mac dev doctor                          Diagnose host auth + tools
  mac dev stacks                          List available stacks
  mac dev flavors <stack>                 List flavors for a stack
  mac dev test [bats-args...]             Run the dev test suite (bats)

${BOLD}Stacks:${RESET}    python | node | go | rust | cpp | csharp | java
${BOLD}Examples:${RESET}
  mac dev create api --python --fastapi
  mac dev create ml  --python --notebooks --pytorch
  mac dev create web --node --vite-ts
  mac dev create cli --rust
  mac dev create rt  --cpp
EOF
}

# ── Helpers ─────────────────────────────────────────────────────────────────

list_stacks() {
  ls "$TEMPLATES/stacks/"*.json 2>/dev/null | xargs -n1 basename | sed 's/\.json$//'
}

list_flavors() {
  local stack="$1"
  ls "$TEMPLATES/flavors/" 2>/dev/null \
    | grep "^${stack}-" \
    | sed "s/^${stack}-//;s/\.json$//;s/\.post\.sh$//" \
    | sort -u
}

# Project names become directory names, JSON values, and (sometimes) shell
# tokens — restrict to a portable subset.
validate_project_name() {
  local n="$1"
  if [[ ! "$n" =~ ^[a-zA-Z0-9._-]+$ ]]; then
    fail "invalid project name: '$n' (allowed: a-z A-Z 0-9 . _ -)"
    return 1
  fi
}

# Sanitize an arbitrary string into a safe project name (used by `init` to
# infer name from $PWD basename). Lowercases, replaces non-portable chars
# with '-', collapses repeats, trims leading/trailing dashes.
sanitize_name() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | tr -c 'a-z0-9._-' '-' \
    | sed 's/--*/-/g; s/^-//; s/-$//'
}

# Suggest the closest match (Levenshtein) from a space-separated candidate
# list. Returns nothing when the closest is too far to be a typo.
# Used to power "did you mean ...?" hints on unknown stack/flavor flags.
suggest_match() {
  local typed="$1" candidates="$2"
  python3 - "$typed" "$candidates" 2>/dev/null <<'PY'
import sys
typed = sys.argv[1]
cands = sys.argv[2].split()
if not cands:
    sys.exit(0)
def lev(a, b):
    if not a: return len(b)
    if not b: return len(a)
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a):
        curr = [i + 1]
        for j, cb in enumerate(b):
            curr.append(min(curr[-1] + 1, prev[j + 1] + 1,
                            prev[j] + (0 if ca == cb else 1)))
        prev = curr
    return prev[-1]
best = min(cands, key=lambda c: lev(typed, c))
threshold = max(2, len(typed) // 2)
if lev(typed, best) <= threshold:
    print(best)
PY
}

# ── create ──────────────────────────────────────────────────────────────────

dev_create() {
  local name="" stack="" target_dir="" force=0
  declare -a flavors=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --in)      target_dir="$2"; shift 2 ;;
      --force|-f) force=1; shift ;;
      --help|-h) usage; exit 0 ;;
      --*)
        local opt="${1#--}"
        if [[ " $(list_stacks | tr '\n' ' ') " == *" $opt "* ]]; then
          # Reject second --<stack> flag — ambiguous which one wins.
          if [[ -n "$stack" && "$stack" != "$opt" ]]; then
            fail "multiple stacks specified: --${stack} and --${opt}"
            exit 1
          fi
          stack="$opt"
        else
          flavors+=("$opt")
        fi
        shift
        ;;
      *)
        [[ -z "$name" ]] && name="$1"
        shift
        ;;
    esac
  done

  [[ -z "$name" ]]  && { fail "name required";   usage; exit 1; }
  validate_project_name "$name" || exit 1

  # If no stack was matched but flavors were collected, the user most likely
  # mistyped a stack name (which falls through to flavors[]). Suggest one.
  if [[ -z "$stack" && ${#flavors[@]} -gt 0 ]]; then
    local guess
    guess="$(suggest_match "${flavors[0]}" "$(list_stacks | tr '\n' ' ')")"
    if [[ -n "$guess" ]]; then
      fail "stack required — did you mean --${guess}? (got --${flavors[0]})"
      exit 1
    fi
  fi
  [[ -z "$stack" ]] && { fail "stack required (--python|--node|--go|--rust|--cpp|--csharp|--java)"; exit 1; }

  target_dir="${target_dir:-$PWD/$name}"

  # Pre-flight: target writable.
  if ! mkdir -p "$target_dir" 2>/dev/null; then
    fail "cannot create target dir (permission denied?): $target_dir"
    exit 1
  fi
  if [[ ! -w "$target_dir" ]]; then
    fail "target dir not writable: $target_dir"
    exit 1
  fi

  # Pre-flight: warn about missing host bind-mount sources. We do NOT abort —
  # the user might be generating a config to commit and run elsewhere — but we
  # surface what would block container start on this machine.
  local missing_mounts=()
  [[ -e "$HOME/.gitconfig.local" ]] || missing_mounts+=("~/.gitconfig.local")
  [[ -d "$HOME/.claude" ]]          || missing_mounts+=("~/.claude")
  [[ -d "$HOME/.ssh" ]]             || missing_mounts+=("~/.ssh")
  if (( ${#missing_mounts[@]} > 0 )); then
    warn "host bind-mount sources missing: ${missing_mounts[*]}"
    info "container will refuse to start until these exist (run 'mac dev doctor')"
  fi

  # Refuse to clobber an existing devcontainer unless --force is set.
  local existing="$target_dir/.devcontainer/devcontainer.json"
  if [[ -f "$existing" && $force -eq 0 ]]; then
    fail ".devcontainer already exists at: $existing"
    info "Use --force to overwrite, or 'mac dev upgrade' (when available)"
    exit 1
  fi

  local stack_file="$TEMPLATES/stacks/${stack}.json"
  [[ ! -f "$stack_file" ]] && { fail "unknown stack: $stack"; exit 1; }

  declare -a flavor_files=()
  for f in "${flavors[@]:-}"; do
    [[ -z "$f" ]] && continue
    local fpath="$TEMPLATES/flavors/${stack}-${f}.json"
    if [[ ! -f "$fpath" ]]; then
      fail "unknown flavor for ${stack}: ${f}"
      local guess
      guess="$(suggest_match "$f" "$(list_flavors "$stack" | tr '\n' ' ')")"
      if [[ -n "$guess" ]]; then
        info "did you mean --${guess}?"
      fi
      info "available: $(list_flavors "$stack" | tr '\n' ' ')"
      exit 1
    fi
    flavor_files+=("$fpath")
  done

  mkdir -p "$target_dir/.devcontainer/post-create.d"

  local out="$target_dir/.devcontainer/devcontainer.json"

  # Merge: _base ← stack ← flavors (left to right)
  local layers=("$TEMPLATES/_base/devcontainer.partial.json" "$stack_file")
  for ff in "${flavor_files[@]:-}"; do
    [[ -n "$ff" ]] && layers+=("$ff")
  done

  # Extract known-array fields from every layer (concat + dedupe);
  # then deep-object-merge with `*`; then re-inject the concatenated arrays.
  local exts mounts ports
  exts=$(jq -s   '[.[] | .customizations.vscode.extensions // []] | add // [] | unique' "${layers[@]}")
  mounts=$(jq -s '[.[] | .mounts // []] | add // [] | unique' "${layers[@]}")
  ports=$(jq -s  '[.[] | .forwardPorts // []] | add // [] | unique' "${layers[@]}")

  jq -s --argjson exts "$exts" --argjson mounts "$mounts" --argjson ports "$ports" '
    reduce .[1:][] as $x (.[0]; . * $x)
    | .mounts = $mounts
    | (if $exts | length > 0
        then .customizations.vscode.extensions = $exts
        else . end)
    | (if $ports | length > 0
        then .forwardPorts = $ports
        else del(.forwardPorts) end)
  ' "${layers[@]}" \
    | sed "s/{{NAME}}/${name}/g" > "$out"

  # Runner
  cp "$TEMPLATES/_base/post-create.sh" "$target_dir/.devcontainer/post-create.sh"

  # Base scripts
  cp "$TEMPLATES/_base/post-create.d/"*.sh "$target_dir/.devcontainer/post-create.d/" 2>/dev/null || true

  # Stack post-create
  if [[ -f "$TEMPLATES/stacks/${stack}.post.sh" ]]; then
    cp "$TEMPLATES/stacks/${stack}.post.sh" \
       "$target_dir/.devcontainer/post-create.d/10-${stack}.sh"
  fi

  # Flavor post-creates
  local idx=20
  for f in "${flavors[@]:-}"; do
    [[ -z "$f" ]] && continue
    local fpost="$TEMPLATES/flavors/${stack}-${f}.post.sh"
    if [[ -f "$fpost" ]]; then
      cp "$fpost" "$target_dir/.devcontainer/post-create.d/${idx}-${stack}-${f}.sh"
      idx=$((idx + 1))
    fi
  done

  chmod +x "$target_dir/.devcontainer/post-create.sh" \
           "$target_dir/.devcontainer/post-create.d/"*.sh 2>/dev/null || true

  # Metadata: lets `mac dev upgrade` regenerate without re-asking the user.
  # Schema is intentionally minimal — bump `template_version` if breaking
  # changes ever happen, so upgrade can branch on it.
  local flavors_json="[]"
  if (( ${#flavors[@]} > 0 )); then
    flavors_json="$(printf '%s\n' "${flavors[@]}" | jq -R . | jq -s .)"
  fi
  jq -n \
    --arg name  "$name" \
    --arg stack "$stack" \
    --argjson flavors "$flavors_json" \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{
       template_version: 1,
       name: $name,
       stack: $stack,
       flavors: $flavors,
       generated_at: $ts
     }' > "$target_dir/.devcontainer/.mac-dev.json"

  # .gitignore additions for common artifacts
  local gi="$target_dir/.gitignore"
  touch "$gi"
  for entry in '.venv/' '__pycache__/' 'node_modules/' 'dist/' 'build/' '.DS_Store' '.devcontainer/post-create.d/'; do
    grep -qxF "$entry" "$gi" || echo "$entry" >> "$gi"
  done

  echo ""
  ok "devcontainer ready at: ${out}"
  printf "  ${BOLD}Stack:${RESET}   %s\n" "$stack"
  if (( ${#flavors[@]} > 0 )); then
    printf "  ${BOLD}Flavors:${RESET} %s\n" "$(IFS=,; echo "${flavors[*]}")"
  fi
  echo ""
  printf "Next: ${BOLD}code %s${RESET}\n" "$target_dir"
  printf "      Cmd+Shift+P → ${BOLD}Dev Containers: Reopen in Container${RESET}\n"
}

# ── init ────────────────────────────────────────────────────────────────────
# Like `create`, but for an existing project: scaffolds .devcontainer/ inside
# the current directory (or --in <path>), inferring the project name from
# the directory basename. Stack post-create scripts already check for
# pre-existing project files (pyproject.toml, package.json, ...) and skip
# rather than clobber.

dev_init() {
  local target="$PWD" name=""
  declare -a passthrough=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --in)   target="$2"; shift 2 ;;
      --name) name="$2";   shift 2 ;;
      *)      passthrough+=("$1"); shift ;;
    esac
  done

  if [[ ! -d "$target" ]]; then
    fail "target dir does not exist: $target"
    return 1
  fi

  if [[ -z "$name" ]]; then
    name="$(sanitize_name "$(basename "$target")")"
    if [[ -z "$name" ]]; then
      fail "could not infer project name from '$target' — pass --name"
      return 1
    fi
  fi

  validate_project_name "$name" || return 1

  info "init: name='$name' target='$target'"
  dev_create "$name" --in "$target" "${passthrough[@]}"
}

# ── list ────────────────────────────────────────────────────────────────────

dev_list() {
  printf "${BOLD}Devcontainers found:${RESET}\n\n"
  local found=0
  for root in "$HOME/Dev" "$HOME/boostlingo" "$HOME/Projetos"; do
    [[ ! -d "$root" ]] && continue
    while IFS= read -r f; do
      local dir name image stripped
      dir="$(dirname "$(dirname "$f")")"
      # devcontainer.json may be JSONC (line comments). Strip them before jq.
      stripped="$(sed 's|//.*||' "$f")"
      name="$(echo "$stripped"  | jq -r '.name // "unnamed"' 2>/dev/null || echo "?")"
      image="$(echo "$stripped" | jq -r '.image // "—"'    2>/dev/null | sed 's|.*/||' || echo "?")"
      printf "  ${BOLD}%-25s${RESET} ${GREY}%-30s${RESET} %s\n" \
             "$name" "$image" "${dir/#$HOME/~}"
      found=$((found + 1))
    done < <(find "$root" -maxdepth 4 -path "*/.devcontainer/devcontainer.json" 2>/dev/null)
  done
  if (( found == 0 )); then info "none"; fi
}

# ── open ────────────────────────────────────────────────────────────────────

dev_open() {
  local target="${1:-.}"
  target="$(cd "$target" && pwd)"
  if [[ ! -d "$target/.devcontainer" ]]; then
    fail "no .devcontainer in $target"
    return 1
  fi
  if ! command -v code >/dev/null 2>&1; then
    fail "VSCode 'code' CLI not on PATH"
    return 1
  fi
  code "$target"
  info "VSCode launched. Cmd+Shift+P → 'Dev Containers: Reopen in Container'"
}

# ── validate ────────────────────────────────────────────────────────────────
# Static + host-state checks on a project's .devcontainer config. Surfaces
# everything that would block a container build *before* you launch VSCode.
# Exits non-zero if any error is found; warnings do not fail.

dev_validate() {
  local target="${1:-$PWD}"
  target="$(cd "$target" 2>/dev/null && pwd)" || {
    fail "target dir does not exist: $1"; return 1;
  }

  local f="$target/.devcontainer/devcontainer.json"
  if [[ ! -f "$f" ]]; then
    fail "no devcontainer.json at $f"
    return 1
  fi

  printf "${BOLD}Validating ${target/#$HOME/~}/.devcontainer/devcontainer.json${RESET}\n\n"

  local errors=0 warnings=0
  local stripped
  # Allow JSONC line comments.
  stripped="$(sed 's|//.*||' "$f")"

  # ── 1. JSON well-formed ─────────────────────────────────────────────────
  if ! echo "$stripped" | jq empty 2>/dev/null; then
    fail "JSON parse failed"
    errors=$((errors + 1))
    return $errors
  fi
  ok "JSON parse"

  # ── 2. Required fields ──────────────────────────────────────────────────
  local name image
  name="$(echo "$stripped" | jq -r '.name // empty')"
  image="$(echo "$stripped" | jq -r '.image // empty')"
  local build_dockerfile
  build_dockerfile="$(echo "$stripped" | jq -r '.build.dockerfile // empty')"

  if [[ -z "$name" ]]; then
    fail "missing 'name'"; errors=$((errors + 1))
  else
    ok "name: ${name}"
  fi

  if [[ -z "$image" && -z "$build_dockerfile" ]]; then
    fail "missing both 'image' and 'build.dockerfile' (need at least one)"
    errors=$((errors + 1))
  elif [[ -n "$image" ]]; then
    ok "image: ${image}"
  else
    ok "build.dockerfile: ${build_dockerfile}"
  fi

  # ── 3. Mount source paths exist on host ─────────────────────────────────
  while IFS= read -r mount; do
    [[ -z "$mount" ]] && continue
    # Extract source=... value from the comma-separated mount string.
    local src
    src="$(echo "$mount" | sed -n 's/.*source=\([^,]*\).*/\1/p')"
    [[ -z "$src" ]] && continue
    # Resolve ${localEnv:HOME} → $HOME.
    local resolved="${src//\$\{localEnv:HOME\}/$HOME}"
    if [[ -e "$resolved" ]]; then
      ok "mount source exists: ${resolved/#$HOME/~}"
    else
      warn "mount source missing on host: ${resolved/#$HOME/~}"
      info "container start will fail until this exists"
      warnings=$((warnings + 1))
    fi
  done < <(echo "$stripped" | jq -r '.mounts[]? // empty')

  # ── 4. post-create scripts executable ───────────────────────────────────
  local pcr="$target/.devcontainer/post-create.sh"
  if [[ -f "$pcr" ]]; then
    if [[ -x "$pcr" ]]; then
      ok "post-create.sh executable"
    else
      warn "post-create.sh not executable (chmod +x recommended)"
      warnings=$((warnings + 1))
    fi
  fi

  local pcd="$target/.devcontainer/post-create.d"
  if [[ -d "$pcd" ]]; then
    local n_scripts non_exec
    n_scripts=$(find "$pcd" -name '*.sh' -type f 2>/dev/null | wc -l | tr -d ' ')
    non_exec=$(find "$pcd" -name '*.sh' -type f ! -perm -u+x 2>/dev/null | wc -l | tr -d ' ')
    if (( non_exec > 0 )); then
      warn "post-create.d: ${non_exec}/${n_scripts} scripts not executable"
      warnings=$((warnings + 1))
    else
      ok "post-create.d: ${n_scripts} scripts, all executable"
    fi
  fi

  # ── 5. Image already pulled locally? (informational) ────────────────────
  if [[ -n "$image" ]] && command -v docker >/dev/null 2>&1 && docker info &>/dev/null; then
    if docker image inspect "$image" >/dev/null 2>&1; then
      ok "image already pulled locally"
    else
      info "image not pulled locally — first build will fetch (~mins)"
    fi
  fi

  echo ""
  if (( errors > 0 )); then
    fail "${errors} error(s), ${warnings} warning(s)"
    return 1
  fi
  ok "validate passed (${warnings} warning(s))"
  return 0
}

# ── upgrade / diff ──────────────────────────────────────────────────────────
# Regenerate a project's devcontainer.json from the current templates, using
# the stack + flavors recorded in .devcontainer/.mac-dev.json at create
# time. `diff` previews changes without writing.

# DEV_BIN points back at this script (used by upgrade/diff to recurse).
DEV_BIN="${BASH_SOURCE[0]}"

dev_upgrade() {
  local target="$PWD" force=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --force|-f) force=1; shift ;;
      *)          target="$1"; shift ;;
    esac
  done
  target="$(cd "$target" 2>/dev/null && pwd)" || { fail "no such dir"; return 1; }

  local meta="$target/.devcontainer/.mac-dev.json"
  if [[ ! -f "$meta" ]]; then
    fail "no .devcontainer/.mac-dev.json — was this devcontainer generated by mac dev?"
    info "Re-create with: mac dev create <name> --<stack> [--<flavor>...] --in $target --force"
    return 1
  fi

  local name stack
  name="$(jq -r .name  "$meta")"
  stack="$(jq -r .stack "$meta")"
  declare -a flavor_args=()
  while IFS= read -r f; do
    [[ -n "$f" ]] && flavor_args+=("--$f")
  done < <(jq -r '.flavors[]?' "$meta")

  info "upgrading: name=$name stack=$stack flavors=${flavor_args[*]:-(none)}"

  # Always passes --force here: upgrade explicitly overwrites by design.
  if (( ${#flavor_args[@]} > 0 )); then
    "$DEV_BIN" create "$name" "--$stack" "${flavor_args[@]}" --in "$target" --force
  else
    "$DEV_BIN" create "$name" "--$stack" --in "$target" --force
  fi
}

dev_diff() {
  local target="${1:-$PWD}"
  target="$(cd "$target" 2>/dev/null && pwd)" || { fail "no such dir"; return 1; }

  local meta="$target/.devcontainer/.mac-dev.json"
  if [[ ! -f "$meta" ]]; then
    fail "no .devcontainer/.mac-dev.json — was this devcontainer generated by mac dev?"
    return 1
  fi

  local name stack
  name="$(jq -r .name  "$meta")"
  stack="$(jq -r .stack "$meta")"
  declare -a flavor_args=()
  while IFS= read -r f; do
    [[ -n "$f" ]] && flavor_args+=("--$f")
  done < <(jq -r '.flavors[]?' "$meta")

  local tmp
  tmp="$(mktemp -d)"
  trap "rm -rf '$tmp'" RETURN

  if (( ${#flavor_args[@]} > 0 )); then
    "$DEV_BIN" create "$name" "--$stack" "${flavor_args[@]}" --in "$tmp/regen" >/dev/null
  else
    "$DEV_BIN" create "$name" "--$stack" --in "$tmp/regen" >/dev/null
  fi

  local cur="$target/.devcontainer/devcontainer.json"
  local new="$tmp/regen/.devcontainer/devcontainer.json"

  printf "${BOLD}Drift between %s and current template:${RESET}\n\n" \
    "${cur/#$HOME/~}"
  if diff <(jq -S . "$cur") <(jq -S . "$new") >/dev/null; then
    ok "no changes — already up to date"
  else
    # `diff` exits 1 when files differ; with set -e + pipefail this would
    # kill the script. Wrap so a normal "drift detected" run is success.
    diff -u <(jq -S . "$cur") <(jq -S . "$new") | sed 's/^/  /' || true
    echo ""
    info "apply with: mac dev upgrade ${target/#$HOME/~}"
  fi
}

# ── rebuild / clean ─────────────────────────────────────────────────────────

dev_rebuild() {
  local target="${1:-$PWD}"
  target="$(cd "$target" 2>/dev/null && pwd)" || { fail "no such dir"; return 1; }

  if [[ ! -f "$target/.devcontainer/devcontainer.json" ]]; then
    fail "no devcontainer at $target"
    return 1
  fi

  if ! command -v devcontainer >/dev/null 2>&1; then
    fail "devcontainer CLI not installed"
    info "Install: npm i -g @devcontainers/cli"
    return 1
  fi

  info "rebuilding (no-cache)…"
  devcontainer up --workspace-folder "$target" --remove-existing-container --build-no-cache
}

dev_clean() {
  local target="$PWD" force=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --force|-f) force=1; shift ;;
      *)          target="$1"; shift ;;
    esac
  done
  target="$(cd "$target" 2>/dev/null && pwd)" || { fail "no such dir"; return 1; }

  local d="$target/.devcontainer"
  if [[ ! -d "$d" ]]; then
    info "nothing to clean — no .devcontainer at $target"
    return 0
  fi

  if (( ! force )) && [[ -t 0 && -t 1 ]]; then
    printf "Remove %s ? [y/N] " "$d"
    local ans
    read -r ans
    [[ "$ans" =~ ^[yY] ]] || { info "aborted"; return 0; }
  elif (( ! force )); then
    fail "non-interactive — pass --force to confirm"
    return 1
  fi

  rm -rf "$d"
  ok "removed $d"
}

# ── mount-claude ────────────────────────────────────────────────────────────

dev_mount_claude() {
  local f="./.devcontainer/devcontainer.json"
  [[ ! -f "$f" ]] && { fail "no $f"; return 1; }

  local mount='source=${localEnv:HOME}/.claude,target=/home/vscode/.claude,type=bind,consistency=cached'
  if grep -q '/.claude' "$f"; then
    info "already mounted"
    return 0
  fi

  jq --arg m "$mount" '.mounts = ((.mounts // []) + [$m])' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  ok "claude bind mount added to $f"
}

# ── sync-ext ────────────────────────────────────────────────────────────────

dev_sync_ext() {
  local code_settings="$HOME/Library/Application Support/Code/User/settings.json"
  [[ ! -f "$code_settings" ]] && { fail "VSCode settings not found at $code_settings"; return 1; }

  local exts
  exts=$(grep '^vscode "' "$DOTFILES/Brewfile" \
         | sed 's/vscode "//;s/".*//' \
         | jq -R . | jq -s .)

  jq --argjson exts "$exts" '."dev.containers.defaultExtensions" = $exts' "$code_settings" \
    > "$code_settings.tmp" && mv "$code_settings.tmp" "$code_settings"

  ok "synced $(echo "$exts" | jq length) extensions to dev.containers.defaultExtensions"
}

# ── doctor ──────────────────────────────────────────────────────────────────

dev_doctor() {
  printf "${BOLD}Devcontainer environment check${RESET}\n\n"

  local n_keys
  n_keys=$(ssh-add -l 2>/dev/null | grep -cv 'no identities' || true)
  if (( n_keys > 0 )); then
    ok "SSH agent: ${n_keys} key(s) loaded"
  else
    warn "SSH agent empty — git over SSH inside containers will prompt or fail"
    info "Fix: ssh-add --apple-use-keychain ~/.ssh/id_rsa"
  fi

  if gh auth status &>/dev/null; then
    local user
    user=$(gh api user --jq .login 2>/dev/null)
    ok "gh CLI logged in as ${user}"
  else
    warn "gh CLI not logged in (run: gh auth login)"
  fi

  if [[ -f "$HOME/.gitconfig.local" ]]; then
    ok "~/.gitconfig.local present (bind-mounted into containers)"
  else
    warn "~/.gitconfig.local missing — set user.name and user.email there"
  fi

  if [[ -d "$HOME/.claude" ]]; then
    ok "~/.claude present (claude-code auth bind-mounted into containers)"
  else
    info "~/.claude missing — login claude-code on host first to persist auth"
  fi

  if docker info &>/dev/null; then
    ok "Docker daemon reachable"
  else
    fail "Docker not running — start OrbStack"
  fi

  if command -v devcontainer >/dev/null 2>&1; then
    ok "devcontainer CLI: $(devcontainer --version 2>/dev/null | head -1)"
  else
    info "devcontainer CLI absent (optional, for headless rebuilds: npm i -g @devcontainers/cli)"
  fi

  local code_settings="$HOME/Library/Application Support/Code/User/settings.json"
  if [[ -f "$code_settings" ]] && grep -q "dotfiles.repository" "$code_settings"; then
    ok "VSCode dotfiles.repository configured"
  else
    warn "VSCode dotfiles.repository missing — devcontainer setup incomplete"
  fi

  echo ""
}

# ── stacks / flavors ────────────────────────────────────────────────────────

dev_stacks() {
  printf "${BOLD}Available stacks:${RESET}\n"
  list_stacks | sed 's/^/  /'
}

dev_flavors_cmd() {
  local stack="${1:-}"
  if [[ -z "$stack" ]]; then
    fail "Usage: mac dev flavors <stack>"
    return 1
  fi
  printf "${BOLD}Flavors for ${stack}:${RESET}\n"
  list_flavors "$stack" | sed 's/^/  /'
}

# ── test ────────────────────────────────────────────────────────────────────

dev_test() {
  if ! command -v bats >/dev/null 2>&1; then
    fail "bats not installed — run: mac add bats-core"
    return 1
  fi
  local tests_dir="$DOTFILES/tests/dev"
  if [[ ! -d "$tests_dir" ]]; then
    fail "test directory missing: $tests_dir"
    return 1
  fi
  exec bats "$@" "$tests_dir"
}

# ── Dispatch ────────────────────────────────────────────────────────────────

cmd="${1:-}"
shift || true

case "$cmd" in
  create)        dev_create "$@" ;;
  init)          dev_init "$@" ;;
  list|ls)       dev_list ;;
  open)          dev_open "$@" ;;
  validate)      dev_validate "$@" ;;
  upgrade)       dev_upgrade "$@" ;;
  diff)          dev_diff "$@" ;;
  rebuild)       dev_rebuild "$@" ;;
  clean)         dev_clean "$@" ;;
  mount-claude)  dev_mount_claude ;;
  sync-ext)      dev_sync_ext ;;
  doctor)        dev_doctor ;;
  stacks)        dev_stacks ;;
  flavors)       dev_flavors_cmd "$@" ;;
  test)          dev_test "$@" ;;
  ""|help|-h|--help) usage ;;
  *) fail "unknown subcommand: $cmd"; usage; exit 1 ;;
esac
