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
# 5. Git identity (local, untracked)
# Keeps identity out of repo-managed ~/.gitconfig by using ~/.gitconfig.local.
# ─────────────────────────────────────────────────────────────────────────────
git_config_file_has_key() {
  local file="$1"
  local key="$2"
  git config --file "$file" --get "$key" >/dev/null 2>&1
}

git_config_file_includes_local() {
  local file="$1"
  [[ -e "$file" || -L "$file" ]] || return 1

  local include_path
  while IFS= read -r include_path; do
    case "$include_path" in
      "~/.gitconfig.local"|"$HOME/.gitconfig.local") return 0 ;;
    esac
  done < <(git config --file "$file" --get-all include.path 2>/dev/null || true)

  return 1
}

git_repo_managed_config_path() {
  local global_cfg="$HOME/.gitconfig"

  if [[ -L "$global_cfg" ]]; then
    local link_target
    link_target="$(readlink "$global_cfg")"
    if [[ "$link_target" == /* ]]; then
      echo "$link_target"
    else
      echo "$(cd "$(dirname "$global_cfg")" && pwd)/$link_target"
    fi
    return
  fi

  echo "$DOTFILES/.gitconfig"
}

git_repo_config_has_identity_entries() {
  local file="$1"
  [[ -f "$file" ]] || return 1
  git_config_file_has_key "$file" user.name && return 0
  git_config_file_has_key "$file" user.email && return 0
  return 1
}

resolve_git_identity_seed_values() {
  local __name_var="$1"
  local __email_var="$2"
  local seed_name=""
  local seed_email=""
  local global_name
  local global_email

  global_name="$(git config --global --get user.name 2>/dev/null || true)"
  global_email="$(git config --global --get user.email 2>/dev/null || true)"

  if [[ -n "$global_name" && -n "$global_email" ]]; then
    seed_name="$global_name"
    seed_email="$global_email"
  else
    [[ -n "$global_name" ]] && seed_name="$global_name"
    [[ -n "$global_email" ]] && seed_email="$global_email"

    if [[ -z "$seed_email" ]]; then
      seed_email="$(git config --get user.email 2>/dev/null || true)"
    fi

    if [[ -z "$seed_name" ]]; then
      local dscl_name
      dscl_name="$(dscl . -read "/Users/$USER" RealName 2>/dev/null | sed -n 's/^RealName:[[:space:]]*//p' | head -1)"
      if [[ -n "$dscl_name" ]]; then
        seed_name="$dscl_name"
      elif id -F >/dev/null 2>&1; then
        seed_name="$(id -F 2>/dev/null || true)"
      fi
    fi
  fi

  printf -v "$__name_var" '%s' "$seed_name"
  printf -v "$__email_var" '%s' "$seed_email"
}

append_missing_identity_placeholders() {
  local file="$1"
  local need_name="$2"
  local need_email="$3"
  local add_name="no"
  local add_email="no"

  if [[ "$need_name" == "yes" ]] && ! grep -Eq '^[[:space:]]*#[[:space:]]*name[[:space:]]*=' "$file" 2>/dev/null; then
    add_name="yes"
  fi
  if [[ "$need_email" == "yes" ]] && ! grep -Eq '^[[:space:]]*#[[:space:]]*email[[:space:]]*=' "$file" 2>/dev/null; then
    add_email="yes"
  fi

  if [[ "$add_name" == "no" && "$add_email" == "no" ]]; then
    return 1
  fi

  {
    printf '\n[user]\n'
    [[ "$add_name" == "yes" ]] && printf '\t# name =\n'
    [[ "$add_email" == "yes" ]] && printf '\t# email =\n'
  } >> "$file"

  return 0
}

step_git_identity() {
  section "Git Identity"

  local global_cfg="$HOME/.gitconfig"
  local local_cfg="$HOME/.gitconfig.local"
  local repo_cfg
  repo_cfg="$(git_repo_managed_config_path)"

  local is_symlink="no"
  local includes_local="no"
  local local_exists="no"
  local local_has_name="no"
  local local_has_email="no"
  local repo_has_identity="no"

  [[ -L "$global_cfg" ]] && is_symlink="yes"
  git_config_file_includes_local "$global_cfg" && includes_local="yes"
  [[ -f "$local_cfg" ]] && local_exists="yes"

  if [[ "$local_exists" == "yes" ]]; then
    git_config_file_has_key "$local_cfg" user.name && local_has_name="yes"
    git_config_file_has_key "$local_cfg" user.email && local_has_email="yes"
  fi

  git_repo_config_has_identity_entries "$repo_cfg" && repo_has_identity="yes"

  info "~/.gitconfig is symlink? $is_symlink"
  info "~/.gitconfig includes ~/.gitconfig.local? $includes_local"
  info "~/.gitconfig.local exists? $local_exists"
  info "~/.gitconfig.local has user.name? $local_has_name"
  info "~/.gitconfig.local has user.email? $local_has_email"
  info "repo-managed config has user.name/email? $repo_has_identity"

  if $CHECK_ONLY; then return; fi

  local seed_name
  local seed_email
  resolve_git_identity_seed_values seed_name seed_email

  if [[ ! -f "$local_cfg" ]]; then
    : > "$local_cfg"
    chmod 0600 "$local_cfg" 2>/dev/null || true
    record_applied "~/.gitconfig.local created"
  fi

  if ! git_config_file_has_key "$local_cfg" user.name && [[ -n "$seed_name" ]]; then
    git config --file "$local_cfg" user.name "$seed_name"
    record_applied "~/.gitconfig.local: user.name set"
  fi

  if ! git_config_file_has_key "$local_cfg" user.email && [[ -n "$seed_email" ]]; then
    git config --file "$local_cfg" user.email "$seed_email"
    record_applied "~/.gitconfig.local: user.email set"
  fi

  local need_name_placeholder="no"
  local need_email_placeholder="no"
  git_config_file_has_key "$local_cfg" user.name || need_name_placeholder="yes"
  git_config_file_has_key "$local_cfg" user.email || need_email_placeholder="yes"

  if append_missing_identity_placeholders "$local_cfg" "$need_name_placeholder" "$need_email_placeholder"; then
    record_applied "~/.gitconfig.local placeholders added for missing identity"
  fi

  if [[ ! -e "$global_cfg" && ! -L "$global_cfg" ]]; then
    : > "$global_cfg"
    record_applied "~/.gitconfig created"
  fi

  if git_config_file_includes_local "$global_cfg"; then
    ok "~/.gitconfig already includes ~/.gitconfig.local"
  else
    git config --file "$global_cfg" --add include.path "~/.gitconfig.local"
    record_applied "~/.gitconfig include added (~/.gitconfig.local)"
  fi

  repo_cfg="$(git_repo_managed_config_path)"
  if [[ -f "$repo_cfg" ]]; then
    local removed_any="no"

    if git_config_file_has_key "$repo_cfg" user.name; then
      git config --file "$repo_cfg" --unset-all user.name || true
      removed_any="yes"
    fi
    if git_config_file_has_key "$repo_cfg" user.email; then
      git config --file "$repo_cfg" --unset-all user.email || true
      removed_any="yes"
    fi

    if [[ "$removed_any" == "yes" ]]; then
      if ! grep -qF "# user.name and user.email must live in ~/.gitconfig.local" "$repo_cfg" 2>/dev/null; then
        printf '\n# user.name and user.email must live in ~/.gitconfig.local\n' >> "$repo_cfg"
      fi
      record_applied "repo-managed gitconfig identity keys removed"
    else
      ok "repo-managed gitconfig has no user.name/user.email keys"
    fi
  else
    record_warning "Repo-managed gitconfig not found at $repo_cfg"
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# 6. mise — toolchain manager
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
# 7. Shell configuration
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
# 8. macOS system preferences
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
# 9. sudo authentication (Touch ID / Apple Watch + credential cache)
#
# Rollback:
#   - Remove /etc/pam.d/sudo_local to revert PAM behavior.
#   - sudo defaults delete /Library/Preferences/com.apple.security.authorization.plist ignoreArd
#     to revert Apple Watch approval helper behavior.
#   - Remove /etc/sudoers.d/99-timestamp-timeout to revert sudo timeout.
# ─────────────────────────────────────────────────────────────────────────────
pam_tid_module_present() {
  [[ -e "/usr/lib/pam/pam_tid.so" ]] && return 0
  compgen -G "/usr/lib/pam/pam_tid.so.*" > /dev/null
}

sudo_local_pam_tid_enabled() {
  local pam_file="/etc/pam.d/sudo_local"
  [[ -f "$pam_file" ]] || return 1
  grep -Eq '^[[:space:]]*auth[[:space:]]+sufficient[[:space:]]+pam_tid\.so([[:space:]]|$)' "$pam_file" 2>/dev/null
}

read_ignoreard_state() {
  local raw
  local raw_upper
  raw="$(defaults read /Library/Preferences/com.apple.security.authorization.plist ignoreArd 2>/dev/null || true)"
  raw_upper="$(printf '%s' "$raw" | tr '[:lower:]' '[:upper:]')"
  case "$raw_upper" in
    1|TRUE|YES) echo "TRUE" ;;
    0|FALSE|NO) echo "FALSE" ;;
    *) echo "absent" ;;
  esac
}

read_timestamp_timeout_value() {
  local timeout_file="/etc/sudoers.d/99-timestamp-timeout"
  [[ -f "$timeout_file" ]] || { echo "missing"; return; }

  local line value
  line="$(awk '/^[[:space:]]*Defaults[[:space:]]+.*timestamp_timeout[[:space:]]*=/{print; exit}' "$timeout_file" 2>/dev/null || true)"

  if [[ -z "$line" ]]; then
    line="$(sudo -n awk '/^[[:space:]]*Defaults[[:space:]]+.*timestamp_timeout[[:space:]]*=/{print; exit}' "$timeout_file" 2>/dev/null || true)"
  fi

  [[ -z "$line" ]] && { echo "missing"; return; }

  value="$(printf '%s\n' "$line" | sed -E 's/.*timestamp_timeout[[:space:]]*=[[:space:]]*([^[:space:],#]+).*/\1/')"
  [[ -n "$value" ]] && echo "$value" || echo "missing"
}

step_touchid_sudo() {
  section "sudo authentication"

  local pam_file="/etc/pam.d/sudo_local"
  local pam_template="/etc/pam.d/sudo_local.template"
  local pam_line="auth       sufficient     pam_tid.so"
  local timeout_file="/etc/sudoers.d/99-timestamp-timeout"
  local timeout_line="Defaults timestamp_timeout=15"
  local disable_watch="${DISABLE_WATCH_APPROVE:-0}"

  local pam_present="no"
  local sudo_local_exists="no"
  local sudo_local_enabled="no"
  local ignoreard_state
  local timestamp_timeout_value

  pam_tid_module_present && pam_present="yes"
  [[ -f "$pam_file" ]] && sudo_local_exists="yes"
  sudo_local_pam_tid_enabled && sudo_local_enabled="yes"
  ignoreard_state="$(read_ignoreard_state)"
  timestamp_timeout_value="$(read_timestamp_timeout_value)"

  info "pam_tid module present? $pam_present"
  if [[ "$pam_present" == "no" ]]; then
    info "pam_tid status: pam_tid not present"
  fi
  info "sudo_local exists? $sudo_local_exists"
  if [[ "$pam_present" == "yes" && "$sudo_local_enabled" == "yes" ]]; then
    info "sudo_local pam_tid line enabled? yes (configured)"
  else
    info "sudo_local pam_tid line enabled? $sudo_local_enabled"
  fi
  if [[ "$disable_watch" == "1" ]]; then
    info "ignoreArd set? $ignoreard_state (skipped due DISABLE_WATCH_APPROVE=1)"
  else
    info "ignoreArd set? $ignoreard_state"
  fi
  if [[ "$timestamp_timeout_value" == "missing" ]]; then
    info "timestamp_timeout configured? missing"
  else
    info "timestamp_timeout configured? $timestamp_timeout_value"
  fi

  if $CHECK_ONLY; then return; fi

  local needs_sudo=false
  if [[ "$pam_present" == "yes" && ( "$sudo_local_exists" == "no" || "$sudo_local_enabled" == "no" ) ]]; then
    needs_sudo=true
  fi
  if [[ "$disable_watch" != "1" && "$ignoreard_state" != "TRUE" ]]; then
    needs_sudo=true
  fi
  if [[ "$timestamp_timeout_value" != "15" ]]; then
    needs_sudo=true
  fi

  if $needs_sudo && ! sudo -n true 2>/dev/null; then
    record_error "Sudo auth not cached; run 'sudo -v' once, then re-run bootstrap (no prompts are used here)"
    return
  fi

  if [[ "$pam_present" == "yes" ]]; then
    if [[ ! -f "$pam_file" ]]; then
      if [[ -f "$pam_template" ]]; then
        sudo -n cp "$pam_template" "$pam_file"
        record_applied "$pam_file created from template"
      else
        record_error "Missing $pam_template; cannot safely create $pam_file"
      fi
    fi

    if [[ -f "$pam_file" ]]; then
      local pam_before pam_after
      pam_before="$(mktemp)"
      pam_after="$(mktemp)"

      if sudo -n cat "$pam_file" > "$pam_before"; then
        awk -v canonical="$pam_line" '
          BEGIN { found = 0 }
          /^[[:space:]]*#?[[:space:]]*auth[[:space:]]+.*pam_tid\.so([[:space:]].*)?$/ {
            if (!found) {
              print canonical
              found = 1
            }
            next
          }
          { print }
          END {
            if (!found) print canonical
          }
        ' "$pam_before" > "$pam_after"

        if ! cmp -s "$pam_before" "$pam_after"; then
          sudo -n install -m 0644 "$pam_after" "$pam_file"
          record_applied "$pam_file updated (pam_tid configured)"
        else
          ok "$pam_file already configured"
        fi
      else
        record_error "Failed to read $pam_file with sudo"
      fi

      rm -f "$pam_before" "$pam_after"
    fi
  else
    info "pam_tid not present; skipping sudo_local changes"
  fi

  if [[ "$disable_watch" == "1" ]]; then
    info "Skipping Apple Watch helper (DISABLE_WATCH_APPROVE=1)"
  elif [[ "$ignoreard_state" == "TRUE" ]]; then
    ok "Apple Watch helper already enabled (ignoreArd=TRUE)"
  else
    sudo -n defaults write /Library/Preferences/com.apple.security.authorization.plist ignoreArd -bool TRUE
    record_applied "Apple Watch helper enabled (ignoreArd=TRUE)"
  fi

  if [[ "$timestamp_timeout_value" == "15" ]]; then
    ok "sudo timestamp_timeout already 15"
  else
    local timeout_tmp
    timeout_tmp="$(mktemp)"
    printf '%s\n' "$timeout_line" > "$timeout_tmp"
    sudo -n install -m 0440 "$timeout_tmp" "$timeout_file"

    if sudo -n visudo -cf "$timeout_file" >/dev/null 2>&1; then
      record_applied "sudo timestamp_timeout configured to 15"
    else
      sudo -n rm -f "$timeout_file"
      record_error "Invalid sudoers fragment; removed $timeout_file"
    fi

    rm -f "$timeout_tmp"
  fi
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
  step_git_identity
  step_mise
  step_shell
  step_macos_defaults
  step_touchid_sudo

  print_summary
}

main
