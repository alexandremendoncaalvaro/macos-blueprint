#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# mac — single entry point for managing macOS system state
#
# Usage:
#   mac add <name>             Install and track in Brewfile
#   mac remove <name>          Uninstall and remove from Brewfile
#   mac list                   Show everything tracked in Brewfile
#   mac status                 Quick health check
#   mac check                  Full bootstrap --check
#   mac sync                   Full bootstrap apply
#   mac lock                   Regenerate Brewfile.lock.json
#   mac update                 Update all packages and commit lockfile
#   mac cleanup                Remove old caches and unused packages
#   mac push                   Push dotfiles to remote
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BREWFILE="$DOTFILES/Brewfile"
LOCKSCRIPT="$DOTFILES/scripts/brew-lock.py"

RED='\033[1;31m'; GREEN='\033[1;32m'; YELLOW='\033[1;33m'
BLUE='\033[1;34m'; BOLD='\033[1m'; RESET='\033[0m'

usage() {
  cat <<EOF
${BOLD}mac${RESET} — manage macOS system state

${BOLD}Package management:${RESET}
  mac add <name> [--cask|--formula|--vscode]   Install and track
  mac remove <name>                            Uninstall and untrack
  mac list                                     Show tracked packages
  mac update                                   Upgrade all + commit lockfile

${BOLD}System:${RESET}
  mac status                                   Quick health check
  mac check                                    Full diagnostic (no changes)
  mac sync                                     Apply all fixes
  mac cleanup                                  Remove caches and unused packages

${BOLD}Repo:${RESET}
  mac lock                                     Regenerate Brewfile.lock.json
  mac push                                     Push dotfiles to remote
EOF
  exit 1
}

update_lock() {
  if [[ -x "$LOCKSCRIPT" ]] && command -v python3 &>/dev/null; then
    python3 "$LOCKSCRIPT"
  fi
}

auto_commit() {
  local msg="$1"
  cd "$DOTFILES"
  git add Brewfile Brewfile.lock.json 2>/dev/null || true
  if ! git diff --cached --quiet 2>/dev/null; then
    git commit -m "$msg"
    printf "${GREEN}Committed: %s${RESET}\n" "$msg"
  fi
}

# ── Detect package type from Brewfile or brew info ──────────────────────────
detect_type() {
  local name="$1"

  if grep -q "^brew \"$name\"" "$BREWFILE" 2>/dev/null; then
    echo "formula"; return
  fi
  if grep -q "^cask \"$name\"" "$BREWFILE" 2>/dev/null; then
    echo "cask"; return
  fi
  if grep -q "^vscode \"$name\"" "$BREWFILE" 2>/dev/null; then
    echo "vscode"; return
  fi

  if brew info --cask "$name" &>/dev/null 2>&1; then
    echo "cask"; return
  fi
  if brew info --formula "$name" &>/dev/null 2>&1; then
    echo "formula"; return
  fi
  if [[ "$name" == *.* ]]; then
    echo "vscode"; return
  fi

  echo "unknown"
}

# ── Add ─────────────────────────────────────────────────────────────────────
cmd_add() {
  local name="" type=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --cask)    type="cask"; shift ;;
      --formula) type="formula"; shift ;;
      --vscode)  type="vscode"; shift ;;
      *)         name="$1"; shift ;;
    esac
  done

  [[ -z "$name" ]] && { echo "Usage: mac add <name> [--cask|--formula|--vscode]"; exit 1; }

  [[ -z "$type" ]] && type=$(detect_type "$name")

  if [[ "$type" == "unknown" ]]; then
    printf "${RED}Could not detect type for '%s'. Use --cask, --formula, or --vscode.${RESET}\n" "$name"
    exit 1
  fi

  local keyword
  case "$type" in
    formula) keyword="brew" ;;
    cask)    keyword="cask" ;;
    vscode)  keyword="vscode" ;;
  esac

  if grep -q "^${keyword} \"$name\"" "$BREWFILE" 2>/dev/null; then
    printf "${YELLOW}Already in Brewfile: %s \"%s\"${RESET}\n" "$keyword" "$name"
  else
    echo "${keyword} \"${name}\"" >> "$BREWFILE"
    printf "${GREEN}Added to Brewfile: %s \"%s\"${RESET}\n" "$keyword" "$name"
  fi

  case "$type" in
    formula) brew install "$name" ;;
    cask)    brew install --cask "$name" ;;
    vscode)  code --install-extension "$name" ;;
  esac

  update_lock
  auto_commit "feat(brew): add $name"
}

# ── Remove ──────────────────────────────────────────────────────────────────
cmd_remove() {
  local name="${1:-}"
  [[ -z "$name" ]] && { echo "Usage: mac remove <name>"; exit 1; }

  local type
  type=$(detect_type "$name")

  case "$type" in
    formula)
      brew uninstall "$name" 2>/dev/null && printf "${GREEN}Uninstalled formula: %s${RESET}\n" "$name" \
        || printf "${YELLOW}Formula '%s' not installed (removing from Brewfile anyway)${RESET}\n" "$name"
      ;;
    cask)
      brew uninstall --cask "$name" 2>/dev/null && printf "${GREEN}Uninstalled cask: %s${RESET}\n" "$name" \
        || printf "${YELLOW}Cask '%s' not installed (removing from Brewfile anyway)${RESET}\n" "$name"
      ;;
    vscode)
      code --uninstall-extension "$name" 2>/dev/null && printf "${GREEN}Uninstalled extension: %s${RESET}\n" "$name" \
        || printf "${YELLOW}Extension '%s' not installed (removing from Brewfile anyway)${RESET}\n" "$name"
      ;;
    *)
      printf "${YELLOW}Type unknown for '%s' — removing from Brewfile only${RESET}\n" "$name"
      ;;
  esac

  if grep -q "\"$name\"" "$BREWFILE" 2>/dev/null; then
    sed -i '' "/\"${name}\"/d" "$BREWFILE"
    printf "${GREEN}Removed from Brewfile: %s${RESET}\n" "$name"
  else
    printf "${YELLOW}Not found in Brewfile: %s${RESET}\n" "$name"
  fi

  update_lock
  auto_commit "feat(brew): remove $name"
}

# ── List ────────────────────────────────────────────────────────────────────
cmd_list() {
  printf "${BOLD}Formulae:${RESET}\n"
  grep '^brew ' "$BREWFILE" | sed 's/brew "//;s/".*/  /' | while read -r pkg; do
    local v
    v=$(brew list --formula --versions "$pkg" 2>/dev/null | awk '{print $2}') || true
    printf "  %-30s %s\n" "$pkg" "${v:-${RED}not installed${RESET}}"
  done

  printf "\n${BOLD}Casks:${RESET}\n"
  grep '^cask ' "$BREWFILE" | sed 's/cask "//;s/".*//' | while read -r pkg; do
    local v
    v=$(brew list --cask --versions "$pkg" 2>/dev/null | awk '{print $2}') || true
    printf "  %-30s %s\n" "$pkg" "${v:-${RED}not installed${RESET}}"
  done

  printf "\n${BOLD}VS Code Extensions:${RESET}\n"
  grep '^vscode ' "$BREWFILE" | sed 's/vscode "//;s/".*//' | while read -r ext; do
    if code --list-extensions 2>/dev/null | grep -qi "^${ext}$"; then
      printf "  %-45s ${GREEN}installed${RESET}\n" "$ext"
    else
      printf "  %-45s ${RED}not installed${RESET}\n" "$ext"
    fi
  done
}

# ── Status ──────────────────────────────────────────────────────────────────
cmd_status() {
  printf "${BOLD}mac status${RESET}\n\n"

  # Disk
  local internal external
  internal=$(df -h / | awk 'NR==2{print $4}')
  external=$(df -h /Volumes/MacMini 2>/dev/null | awk 'NR==2{print $4}') || external="not mounted"
  printf "  ${BLUE}Disk:${RESET}     Internal %s free | MacMini SSD %s free\n" "$internal" "$external"

  # Brew
  local outdated
  outdated=$(brew outdated --quiet 2>/dev/null | wc -l | tr -d ' ')
  printf "  ${BLUE}Brew:${RESET}     %s packages outdated\n" "$outdated"

  # mise
  local mise_missing
  mise_missing=$(mise ls --missing 2>/dev/null | wc -l | tr -d ' ')
  printf "  ${BLUE}mise:${RESET}     %s tools missing\n" "$mise_missing"

  # Dotfiles repo
  cd "$DOTFILES"
  local dirty
  dirty=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  local ahead
  ahead=$(git rev-list --count @{u}..HEAD 2>/dev/null || echo "?")
  printf "  ${BLUE}Repo:${RESET}     %s uncommitted | %s unpushed\n" "$dirty" "$ahead"

  # Drift
  local log="$HOME/.local/share/dotfiles/drift-check.log"
  if [[ -f "$log" ]]; then
    local last
    last=$(tail -3 "$log" | head -1)
    printf "  ${BLUE}Drift:${RESET}    %s\n" "$last"
  fi

  echo ""
}

# ── Update ──────────────────────────────────────────────────────────────────
cmd_update() {
  printf "${BOLD}Updating packages...${RESET}\n\n"

  brew update
  brew upgrade
  brew cleanup

  mise upgrade --yes 2>/dev/null || true

  update_lock
  auto_commit "chore: update packages $(date +%Y-%m-%d)"

  printf "\n${GREEN}Done.${RESET}\n"
}

# ── Cleanup ─────────────────────────────────────────────────────────────────
cmd_cleanup() {
  printf "${BOLD}Cleaning up...${RESET}\n\n"

  brew cleanup --prune=all
  mise prune -y 2>/dev/null || true

  # Xcode DerivedData
  local dd="/Volumes/MacMini/DerivedData"
  if [[ -d "$dd" ]]; then
    local dd_size
    dd_size=$(du -sh "$dd" 2>/dev/null | cut -f1)
    printf "  DerivedData: %s — " "$dd_size"
    rm -rf "${dd:?}"/*
    printf "${GREEN}cleaned${RESET}\n"
  fi

  printf "\n${GREEN}Done.${RESET}\n"
}

# ── Push ────────────────────────────────────────────────────────────────────
cmd_push() {
  cd "$DOTFILES"
  git push 2>&1
}

# ── Main ────────────────────────────────────────────────────────────────────
[[ $# -eq 0 ]] && usage

case "$1" in
  add)      shift; cmd_add "$@" ;;
  remove)   shift; cmd_remove "$@" ;;
  list)     cmd_list ;;
  status)   cmd_status ;;
  check)    exec "$DOTFILES/bootstrap.sh" --check ;;
  sync)     exec "$DOTFILES/bootstrap.sh" ;;
  lock)     update_lock ;;
  update)   cmd_update ;;
  cleanup)  cmd_cleanup ;;
  push)     cmd_push ;;
  *)        usage ;;
esac
