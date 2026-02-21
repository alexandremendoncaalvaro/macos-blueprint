#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# bootstrap.sh — macOS development environment
#
# Checks the state of every component before acting.
# Safe to run on a fresh machine or an existing one.
#
# Usage:
#   ./bootstrap.sh           — diagnose + fix everything
#   ./bootstrap.sh --check   — diagnose only, no changes made
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK_ONLY=false
[[ "${1:-}" == "--check" || "${1:-}" == "-c" ]] && CHECK_ONLY=true

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[1;31m'; GREEN='\033[1;32m'; YELLOW='\033[1;33m'
BLUE='\033[1;34m'; GREY='\033[0;90m'; BOLD='\033[1m'; RESET='\033[0m'

ok()      { printf "${GREEN}  ✓${RESET}  %s\n" "$*"; }
fail()    { printf "${RED}  ✗${RESET}  %s\n" "$*"; }
warn()    { printf "${YELLOW}  !${RESET}  %s\n" "$*"; }
info()    { printf "${BLUE}  ·${RESET}  %s\n" "$*"; }
fixed()   { printf "${GREEN}  →${RESET}  %s\n" "$*"; }
section() { printf "\n${BOLD}── %s${RESET}\n\n" "$*"; }

# ── Result tracking ───────────────────────────────────────────────────────────
ERRORS=(); WARNINGS=(); APPLIED=()
record_error()   { ERRORS+=("$1");   fail "$1"; }
record_warning() { WARNINGS+=("$1"); warn "$1"; }
record_applied() { APPLIED+=("$1");  fixed "$1"; }

# ── Helpers ───────────────────────────────────────────────────────────────────

# Homebrew lives at different paths depending on architecture.
brew_prefix() { [[ "$(uname -m)" == "arm64" ]] && echo "/opt/homebrew" || echo "/usr/local"; }

# ─────────────────────────────────────────────────────────────────────────────
# 1. Xcode CLI Tools
# Required by Homebrew and git. Must exist before anything else.
# ─────────────────────────────────────────────────────────────────────────────
step_xcode() {
  section "Xcode CLI Tools"

  if xcode-select -p &>/dev/null; then
    ok "Installed at $(xcode-select -p)"
    return
  fi

  record_error "Xcode CLI tools not installed"

  if $CHECK_ONLY; then return; fi

  info "Launching installer — complete the popup, then re-run this script"
  xcode-select --install 2>/dev/null || true
  exit 1  # Cannot continue; remaining steps need CLT
}

# ─────────────────────────────────────────────────────────────────────────────
# 2. Homebrew
# Checks installation and architecture (Apple Silicon vs Intel prefix).
# ─────────────────────────────────────────────────────────────────────────────
step_homebrew() {
  section "Homebrew"

  local expected
  expected="$(brew_prefix)"

  if ! command -v brew &>/dev/null; then
    record_error "Homebrew not installed"
    if $CHECK_ONLY; then return; fi

    info "Installing Homebrew..."
    NONINTERACTIVE=1 /bin/bash -c \
      "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    eval "$("${expected}/bin/brew" shellenv)"
    record_applied "Homebrew installed"
    return
  fi

  local actual
  actual="$(brew --prefix)"

  # Wrong architecture prefix means the wrong Homebrew was installed.
  if [[ "$actual" != "$expected" ]]; then
    record_error "Homebrew prefix mismatch: got '$actual', expected '$expected'"
    info "This usually means Homebrew was installed for the wrong architecture."
    info "Fix: uninstall and reinstall Homebrew for $(uname -m)."
    return
  fi

  ok "$(brew --version | head -1) at $actual"
}

# ─────────────────────────────────────────────────────────────────────────────
# 3. Homebrew packages
# Uses `brew bundle check` to detect what is missing before installing.
# ─────────────────────────────────────────────────────────────────────────────
step_brewbundle() {
  section "Homebrew Packages"

  local brewfile="$DOTFILES/Brewfile"

  if [[ ! -f "$brewfile" ]]; then
    record_warning "Brewfile not found at $brewfile — skipping"
    return
  fi

  if brew bundle check --file="$brewfile" &>/dev/null; then
    ok "All packages satisfied"
    return
  fi

  # Show exactly what is missing (--verbose lists each missing item).
  local missing_output
  missing_output="$(brew bundle check --file="$brewfile" --verbose 2>&1 | grep -i "not installed\|missing" || true)"
  if [[ -n "$missing_output" ]]; then
    while IFS= read -r line; do
      [[ -n "$line" ]] && record_warning "$line"
    done <<< "$missing_output"
  else
    record_warning "Some packages not satisfied (run brew bundle check --verbose for details)"
  fi

  if $CHECK_ONLY; then return; fi

  info "Running brew bundle install..."
  brew bundle install --file="$brewfile"
  record_applied "brew bundle: all packages installed"
}

# ─────────────────────────────────────────────────────────────────────────────
# 4. Dotfiles symlinks
# Verifies each managed file is:
#   a) present in the repo
#   b) symlinked (not a plain file)
#   c) pointing to the correct source in this repo
# ─────────────────────────────────────────────────────────────────────────────
step_dotfiles() {
  section "Dotfiles"

  local managed=(
    ".zshenv"
    ".gitconfig"
    ".gitignore_global"
    ".config/mise/config.toml"
    ".config/starship.toml"
  )

  for rel in "${managed[@]}"; do
    local src="$DOTFILES/$rel"
    local dst="$HOME/$rel"

    # Source file must exist in the repo.
    if [[ ! -f "$src" ]]; then
      record_warning "Not in repo: dotfiles/$rel — skipping"
      continue
    fi

    # Already a correct symlink — nothing to do.
    if [[ -L "$dst" && "$(readlink "$dst")" == "$src" ]]; then
      ok "~/$rel"
      continue
    fi

    # Exists as a regular file (not a symlink).
    if [[ -f "$dst" && ! -L "$dst" ]]; then
      record_warning "~/$rel is a regular file, not a symlink"
      if $CHECK_ONLY; then continue; fi
      mv "$dst" "${dst}.bak"
      info "Backed up original to ${dst}.bak"
      ln -sf "$src" "$dst"
      record_applied "~/$rel symlinked (original backed up)"
      continue
    fi

    # Symlink exists but points to the wrong place.
    if [[ -L "$dst" ]]; then
      record_warning "~/$rel → $(readlink "$dst") (wrong target)"
      if $CHECK_ONLY; then continue; fi
      ln -sf "$src" "$dst"
      record_applied "~/$rel re-linked to correct source"
      continue
    fi

    # Does not exist at all.
    record_warning "~/$rel not linked"
    if $CHECK_ONLY; then continue; fi
    mkdir -p "$(dirname "$dst")"
    ln -sf "$src" "$dst"
    record_applied "~/$rel symlinked"
  done
}

# ─────────────────────────────────────────────────────────────────────────────
# 5. mise — toolchain manager
# Checks installation, shims on PATH, and runs `mise install` if any
# configured tool is missing. `mise install` is idempotent.
# ─────────────────────────────────────────────────────────────────────────────
step_mise() {
  section "mise"

  if ! command -v mise &>/dev/null; then
    record_error "mise not installed"
    if $CHECK_ONLY; then return; fi
    info "Installing mise via Homebrew..."
    brew install mise
    record_applied "mise installed"
  else
    ok "mise $(mise --version)"
  fi

  # Shims must be on PATH for non-interactive shells (scripts, editors, CI).
  local shims="$HOME/.local/share/mise/shims"
  if echo "$PATH" | tr ':' '\n' | grep -qxF "$shims"; then
    ok "Shims on PATH"
  else
    record_warning "Shims not on PATH — tools unavailable in non-interactive shells"
    info "Fix: ensure ~/.zshenv contains: export PATH=\"\$HOME/.local/share/mise/shims:\$PATH\""
  fi

  # mise doctor — surface any configuration issues.
  local doctor
  doctor="$(mise doctor 2>/dev/null || true)"
  if echo "$doctor" | grep -q "No problems found"; then
    ok "mise doctor: clean"
  else
    local issues
    issues="$(echo "$doctor" | grep -E "^\s+\S+.*: (no|warn)" || true)"
    if [[ -n "$issues" ]]; then
      while IFS= read -r line; do
        record_warning "mise doctor: $line"
      done <<< "$issues"
    fi
  fi

  if $CHECK_ONLY; then
    # In check mode, show what would be installed.
    local missing
    missing="$(mise ls --missing 2>/dev/null | awk '{print $1"@"$2}' || true)"
    if [[ -n "$missing" ]]; then
      while IFS= read -r tool; do
        record_warning "Missing tool: $tool"
      done <<< "$missing"
    else
      ok "All configured tools installed"
    fi
    return
  fi

  # Apply: mise install is a no-op if everything is already installed.
  info "Running mise install..."
  mise install
  record_applied "mise install"
}

# ─────────────────────────────────────────────────────────────────────────────
# 6. Shell configuration
# Verifies .zshenv (PATH dedup + shims) and .zshrc (mise activate + starship).
# Does not touch Kiro CLI or OrbStack managed blocks.
# ─────────────────────────────────────────────────────────────────────────────
step_shell() {
  section "Shell Configuration"

  local zshenv="$HOME/.zshenv"
  local zshrc="$HOME/.zshrc"

  # .zshenv — must be a symlink to our dotfiles version.
  if [[ -L "$zshenv" && "$(readlink "$zshenv")" == "$DOTFILES/.zshenv" ]]; then
    ok ".zshenv → dotfiles (PATH dedup + shims)"
  elif [[ -f "$zshenv" ]]; then
    # Check if it has the right content even if not a symlink.
    if grep -q "typeset -U PATH" "$zshenv" && grep -q "mise/shims" "$zshenv"; then
      ok ".zshenv content correct (not a symlink — run step 4 to fix)"
    else
      record_warning ".zshenv exists but missing PATH dedup or shims config"
    fi
  else
    record_error ".zshenv missing — PATH dedup and mise shims not configured"
  fi

  # .zshrc — managed by Kiro CLI, but must contain these two lines.
  if [[ ! -f "$zshrc" ]]; then
    record_warning ".zshrc not found — will be created by Kiro CLI on install"
    return
  fi

  local required_lines=(
    'eval "$(mise activate zsh)"|mise activate zsh'
    'eval "$(starship init zsh)"|starship init zsh'
  )

  for entry in "${required_lines[@]}"; do
    local pattern="${entry%%|*}"
    local label="${entry##*|}"

    if grep -qF "$pattern" "$zshrc" 2>/dev/null; then
      ok ".zshrc: $label"
    else
      record_warning ".zshrc missing: $label"
      if $CHECK_ONLY; then continue; fi
      printf '\n%s\n' "$pattern" >> "$zshrc"
      record_applied ".zshrc: $label added"
    fi
  done

  # fzf shell integration (ctrl+r history search, ctrl+t file search).
  # Requires fzf >= 0.48. Falls back silently if not installed.
  if command -v fzf &>/dev/null; then
    local fzf_line='source <(fzf --zsh)'
    if grep -qF "$fzf_line" "$zshrc" 2>/dev/null; then
      ok ".zshrc: fzf shell integration"
    else
      record_warning ".zshrc missing: fzf shell integration"
      if ! $CHECK_ONLY; then
        printf '\n%s\n' "$fzf_line" >> "$zshrc"
        record_applied ".zshrc: fzf shell integration added"
      fi
    fi
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# 7. macOS system preferences
# Only preferences that meaningfully affect development workflow.
# Each setting is checked before writing — no unnecessary writes.
#
# Format: "domain|key|flag|write_value|expected_read|description"
#   flag:         -bool, -int, -float, -string
#   write_value:  passed to `defaults write`
#   expected_read: what `defaults read` returns when the setting is applied
# ─────────────────────────────────────────────────────────────────────────────
step_macos_defaults() {
  section "macOS Defaults"

  local settings=(
    # Keyboard: fast repeat, no press-and-hold
    "NSGlobalDomain|KeyRepeat|-int|2|2|keyboard: fast key repeat"
    "NSGlobalDomain|InitialKeyRepeat|-int|15|15|keyboard: short repeat delay"
    "NSGlobalDomain|ApplePressAndHoldEnabled|-bool|false|0|keyboard: key repeat in all apps"
    # Dock
    "com.apple.dock|autohide|-bool|true|1|dock: auto-hide"
    "com.apple.dock|autohide-delay|-float|0|0|dock: no show delay"
    "com.apple.dock|show-recents|-bool|false|0|dock: hide recent apps"
    # Finder
    "com.apple.finder|ShowPathbar|-bool|true|1|finder: path bar"
    "com.apple.finder|ShowStatusBar|-bool|true|1|finder: status bar"
    "com.apple.finder|AppleShowAllFiles|-bool|true|1|finder: show hidden files"
    "com.apple.finder|FXDefaultSearchScope|-string|SCcf|SCcf|finder: search current folder"
    # Screenshots
    "com.apple.screencapture|disable-shadow|-bool|true|1|screenshots: no window shadow"
    "com.apple.screencapture|type|-string|png|png|screenshots: PNG format"
    # Input — critical for developers: prevents silent corruption when pasting code
    "NSGlobalDomain|NSAutomaticSpellingCorrectionEnabled|-bool|false|0|input: disable autocorrect"
    "NSGlobalDomain|NSAutomaticQuoteSubstitutionEnabled|-bool|false|0|input: disable smart quotes"
    "NSGlobalDomain|NSAutomaticDashSubstitutionEnabled|-bool|false|0|input: disable smart dashes"
    # Finder
    "NSGlobalDomain|AppleShowAllExtensions|-bool|true|1|finder: show all file extensions"
    # System — prevent .DS_Store from polluting external volumes and repos
    "com.apple.desktopservices|DSDontWriteNetworkStores|-bool|true|1|system: no .DS_Store on network volumes"
    "com.apple.desktopservices|DSDontWriteUSBStores|-bool|true|1|system: no .DS_Store on USB drives"
  )

  local dock_changed=false
  local finder_changed=false

  for setting in "${settings[@]}"; do
    IFS='|' read -r domain key flag write_val expected label <<< "$setting"

    local actual
    actual="$(defaults read "$domain" "$key" 2>/dev/null || echo "__missing__")"

    if [[ "$actual" == "$expected" ]]; then
      ok "$label"
      continue
    fi

    record_warning "$label — current: '${actual}', expected: '${expected}'"

    if $CHECK_ONLY; then continue; fi

    defaults write "$domain" "$key" "$flag" "$write_val"
    record_applied "defaults: $label"

    [[ "$domain" == "com.apple.dock"   ]] && dock_changed=true
    [[ "$domain" == "com.apple.finder" ]] && finder_changed=true
  done

  if ! $CHECK_ONLY; then
    $dock_changed   && { info "Restarting Dock...";   killall Dock   2>/dev/null || true; }
    $finder_changed && { info "Restarting Finder..."; killall Finder 2>/dev/null || true; }
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# 8. TouchID for sudo
# Writes /etc/pam.d/sudo_local (macOS 13+) so the fingerprint sensor
# can authorize sudo instead of typing the password every time.
# ─────────────────────────────────────────────────────────────────────────────
step_touchid_sudo() {
  section "TouchID for sudo"

  local pam_file="/etc/pam.d/sudo_local"
  local pam_line="auth       sufficient     pam_tid.so"

  if [[ -f "$pam_file" ]] && grep -q "pam_tid.so" "$pam_file" 2>/dev/null; then
    ok "Enabled ($pam_file)"
    return
  fi

  record_warning "Not configured — password required for every sudo"

  if $CHECK_ONLY; then return; fi

  info "Enabling TouchID for sudo (requires sudo)..."
  echo "$pam_line" | sudo tee "$pam_file" > /dev/null
  record_applied "TouchID for sudo enabled"
}

# ─────────────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────────────
print_summary() {
  printf "\n${BOLD}── summary${RESET}\n"

  if [[ ${#APPLIED[@]} -gt 0 ]]; then
    printf "\n  ${GREEN}Applied (${#APPLIED[@]}):${RESET}\n"
    for item in "${APPLIED[@]}"; do printf "    ✓ %s\n" "$item"; done
  fi

  if [[ ${#WARNINGS[@]} -gt 0 ]]; then
    printf "\n  ${YELLOW}Warnings (${#WARNINGS[@]}):${RESET}\n"
    for item in "${WARNINGS[@]}"; do printf "    ! %s\n" "$item"; done
  fi

  if [[ ${#ERRORS[@]} -gt 0 ]]; then
    printf "\n  ${RED}Errors (${#ERRORS[@]}):${RESET}\n"
    for item in "${ERRORS[@]}"; do printf "    ✗ %s\n" "$item"; done
    printf "\n  ${RED}Some errors require manual action.${RESET}\n\n"
    exit 1
  fi

  printf "\n"
  if [[ ${#APPLIED[@]} -eq 0 && ${#WARNINGS[@]} -eq 0 ]]; then
    printf "  ${GREEN}Everything is clean. Nothing to do.${RESET}\n"
  elif $CHECK_ONLY; then
    printf "  Run ${BOLD}./bootstrap.sh${RESET} to apply fixes.\n"
  else
    printf "  ${GREEN}Done.${RESET} Open a new terminal to activate the environment.\n"
  fi
  printf "\n"
}

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────
main() {
  printf "\n${BOLD}── bootstrap ────────────────────────────────────────────────${RESET}\n"
  printf "   Dotfiles: %s\n" "$DOTFILES"
  if $CHECK_ONLY; then
    printf "   Mode:     ${YELLOW}check only${RESET} — no changes will be made\n"
  else
    printf "   Mode:     ${GREEN}apply${RESET}\n"
  fi

  step_xcode
  step_homebrew
  step_brewbundle
  step_dotfiles
  step_mise
  step_shell
  step_macos_defaults
  step_touchid_sudo

  print_summary
}

main
