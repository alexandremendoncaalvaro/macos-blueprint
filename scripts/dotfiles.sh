#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# dotfiles — helper commands for managing the dotfiles repo
#
# Usage:
#   dotfiles add <name>          Add a formula/cask to Brewfile and install it
#   dotfiles remove <name>       Uninstall and remove from Brewfile
#   dotfiles lock                Regenerate Brewfile.lock.json
#   dotfiles check               Run bootstrap --check
#   dotfiles sync                Run bootstrap (full apply)
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BREWFILE="$DOTFILES/Brewfile"
LOCKSCRIPT="$DOTFILES/scripts/brew-lock.py"

RED='\033[1;31m'; GREEN='\033[1;32m'; YELLOW='\033[1;33m'
BOLD='\033[1m'; RESET='\033[0m'

usage() {
  cat <<EOF
Usage: dotfiles <command> [args]

Commands:
  add <name> [--cask|--formula|--vscode]   Install and add to Brewfile
  remove <name>                            Uninstall and remove from Brewfile
  lock                                     Regenerate Brewfile.lock.json
  check                                    Run bootstrap --check
  sync                                     Run bootstrap (full apply)
EOF
  exit 1
}

update_lock() {
  if [[ -x "$LOCKSCRIPT" ]] && command -v python3 &>/dev/null; then
    python3 "$LOCKSCRIPT"
  fi
}

# ── Detect package type from Brewfile or brew info ──────────────────────────
detect_type() {
  local name="$1"

  # Check if already in Brewfile.
  if grep -q "^brew \"$name\"" "$BREWFILE" 2>/dev/null; then
    echo "formula"; return
  fi
  if grep -q "^cask \"$name\"" "$BREWFILE" 2>/dev/null; then
    echo "cask"; return
  fi
  if grep -q "^vscode \"$name\"" "$BREWFILE" 2>/dev/null; then
    echo "vscode"; return
  fi

  # Not in Brewfile — detect from brew.
  if brew info --cask "$name" &>/dev/null; then
    echo "cask"; return
  fi
  if brew info --formula "$name" &>/dev/null; then
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

  [[ -z "$name" ]] && { echo "Usage: dotfiles add <name> [--cask|--formula|--vscode]"; exit 1; }

  [[ -z "$type" ]] && type=$(detect_type "$name")

  if [[ "$type" == "unknown" ]]; then
    printf "${RED}Could not detect type for '%s'. Use --cask, --formula, or --vscode.${RESET}\n" "$name"
    exit 1
  fi

  # Check if already in Brewfile.
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

  # Install.
  case "$type" in
    formula) brew install "$name" ;;
    cask)    brew install --cask "$name" ;;
    vscode)  code --install-extension "$name" ;;
  esac

  update_lock

  printf "\n${BOLD}Don't forget to commit:${RESET}\n"
  printf "  cd ~/dotfiles && git add Brewfile Brewfile.lock.json && git commit -m 'feat(brew): add %s'\n" "$name"
}

# ── Remove ──────────────────────────────────────────────────────────────────
cmd_remove() {
  local name="$1"
  [[ -z "$name" ]] && { echo "Usage: dotfiles remove <name>"; exit 1; }

  local type
  type=$(detect_type "$name")

  # Uninstall.
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

  # Remove from Brewfile (any line matching the name).
  if grep -q "\"$name\"" "$BREWFILE" 2>/dev/null; then
    sed -i '' "/\"${name}\"/d" "$BREWFILE"
    printf "${GREEN}Removed from Brewfile: %s${RESET}\n" "$name"
  else
    printf "${YELLOW}Not found in Brewfile: %s${RESET}\n" "$name"
  fi

  update_lock

  printf "\n${BOLD}Don't forget to commit:${RESET}\n"
  printf "  cd ~/dotfiles && git add Brewfile Brewfile.lock.json && git commit -m 'feat(brew): remove %s'\n" "$name"
}

# ── Main ────────────────────────────────────────────────────────────────────
[[ $# -eq 0 ]] && usage

case "$1" in
  add)     shift; cmd_add "$@" ;;
  remove)  shift; cmd_remove "$@" ;;
  lock)    update_lock ;;
  check)   exec "$DOTFILES/bootstrap.sh" --check ;;
  sync)    exec "$DOTFILES/bootstrap.sh" ;;
  *)       usage ;;
esac
