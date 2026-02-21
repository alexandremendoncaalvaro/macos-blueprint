# Deduplicate PATH entries across all shell init files
typeset -U PATH

# mise shims — available in all shell contexts (scripts, editors, CI)
export PATH="$HOME/.local/share/mise/shims:$PATH"
