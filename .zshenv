# Deduplicate PATH entries across all shell init files
typeset -U PATH

# mise shims — available in all shell contexts (scripts, editors, CI)
export PATH="$HOME/.local/share/mise/shims:$PATH"

# dotfiles helper
export PATH="$HOME/dotfiles/scripts:$PATH"
alias mac='dotfiles.sh'

# External SSD — redirect caches and tool data to external storage.
# Path is configured per machine in ~/.dotfiles.local (not versioned).
# Vars are only exported when the volume is actually mounted.
[[ -f "$HOME/.dotfiles.local" ]] && source "$HOME/.dotfiles.local"
if [[ -n "${DOTFILES_EXTERNAL_SSD:-}" && -d "$DOTFILES_EXTERNAL_SSD" ]]; then
  export HOMEBREW_CACHE="$DOTFILES_EXTERNAL_SSD/Homebrew/Cache"
  export PLAYWRIGHT_BROWSERS_PATH="$DOTFILES_EXTERNAL_SSD/playwright"
  export MISE_DATA_DIR="$DOTFILES_EXTERNAL_SSD/mise"
  export RUSTUP_HOME="$DOTFILES_EXTERNAL_SSD/rustup"
  export CARGO_HOME="$DOTFILES_EXTERNAL_SSD/cargo"
  export npm_config_cache="$DOTFILES_EXTERNAL_SSD/npm-cache"
fi
