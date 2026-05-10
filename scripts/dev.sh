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
  mac dev create <name> --<stack> [--<flavor>...] [--in <path>]
  mac dev list                            List devcontainers in ~/Dev, ~/boostlingo
  mac dev open [path]                     Open path in VS Code (prompts reopen)
  mac dev mount-claude                    Add ~/.claude bind mount to current project
  mac dev sync-ext                        Sync VSCode defaultExtensions with Brewfile
  mac dev doctor                          Diagnose host auth + tools
  mac dev stacks                          List available stacks
  mac dev flavors <stack>                 List flavors for a stack

${BOLD}Stacks:${RESET}    python | node | go | rust | csharp | java
${BOLD}Examples:${RESET}
  mac dev create api --python --fastapi
  mac dev create ml  --python --notebooks --pytorch
  mac dev create web --node --vite-ts
  mac dev create cli --rust
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

# ── create ──────────────────────────────────────────────────────────────────

dev_create() {
  local name="" stack="" target_dir=""
  declare -a flavors=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --in)    target_dir="$2"; shift 2 ;;
      --help|-h) usage; exit 0 ;;
      --*)
        local opt="${1#--}"
        if [[ " $(list_stacks | tr '\n' ' ') " == *" $opt "* ]]; then
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
  [[ -z "$stack" ]] && { fail "stack required (--python|--node|--go|--rust|--csharp|--java)"; exit 1; }

  target_dir="${target_dir:-$PWD/$name}"
  mkdir -p "$target_dir"

  local stack_file="$TEMPLATES/stacks/${stack}.json"
  [[ ! -f "$stack_file" ]] && { fail "unknown stack: $stack"; exit 1; }

  declare -a flavor_files=()
  for f in "${flavors[@]:-}"; do
    [[ -z "$f" ]] && continue
    local fpath="$TEMPLATES/flavors/${stack}-${f}.json"
    if [[ ! -f "$fpath" ]]; then
      fail "unknown flavor for ${stack}: ${f}"
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

# ── Dispatch ────────────────────────────────────────────────────────────────

cmd="${1:-}"
shift || true

case "$cmd" in
  create)        dev_create "$@" ;;
  list|ls)       dev_list ;;
  open)          dev_open "$@" ;;
  mount-claude)  dev_mount_claude ;;
  sync-ext)      dev_sync_ext ;;
  doctor)        dev_doctor ;;
  stacks)        dev_stacks ;;
  flavors)       dev_flavors_cmd "$@" ;;
  ""|help|-h|--help) usage ;;
  *) fail "unknown subcommand: $cmd"; usage; exit 1 ;;
esac
