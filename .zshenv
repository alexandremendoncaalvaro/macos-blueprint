# Deduplicate PATH entries across all shell init files
typeset -U PATH

# mise shims — available in all shell contexts (scripts, editors, CI)
export PATH="$HOME/.local/share/mise/shims:$PATH"

# dotfiles helper
export PATH="$HOME/dotfiles/scripts:$PATH"
alias dotfiles='dotfiles.sh'

# External SSD (MacMini) — redirect caches and tool data to external storage
# These exports are safe even if the volume is not mounted; tools fall back gracefully.
export HOMEBREW_CACHE=/Volumes/MacMini/Homebrew/Cache
export PLAYWRIGHT_BROWSERS_PATH=/Volumes/MacMini/playwright
export MISE_DATA_DIR=/Volumes/MacMini/mise
export RUSTUP_HOME=/Volumes/MacMini/rustup
export CARGO_HOME=/Volumes/MacMini/cargo
export npm_config_cache=/Volumes/MacMini/npm-cache
