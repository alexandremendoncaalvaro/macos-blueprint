# macos-blueprint

Idempotent bootstrap for macOS development machines.  
`./bootstrap.sh` inspects current state and applies only missing configuration.

## Purpose

Keep a Mac development environment reproducible from versioned config in this repository.

## Scope

- Install and validate Xcode Command Line Tools.
- Install Homebrew and reconcile packages from `Brewfile`.
- Link managed dotfiles into `$HOME`.
- Enforce Git identity split (`~/.gitconfig` + `~/.gitconfig.local`).
- Install and validate toolchains with `mise`.
- Configure shell integration (`mise`, `starship`, `fzf`).
- Apply macOS developer defaults.
- Configure `sudo` Touch ID (`pam_tid`) when available.

## Usage

**Fresh machine**
```bash
git clone https://github.com/alexandremendoncaalvaro/macos-blueprint ~/dotfiles
cd ~/dotfiles && ./bootstrap.sh
```

**Existing machine (diagnose only)**
```bash
./bootstrap.sh --check
```

**Apply fixes**
```bash
./bootstrap.sh
```

## Detailed Reference

This section documents what each bootstrap area configures and why it exists.

### 1) Xcode CLI Tools

- Ensures `xcode-select` points to a valid Command Line Tools installation.
- Required for core developer tooling, including Homebrew formulas that compile from source.

### 2) Homebrew

- Verifies Homebrew is installed.
- Verifies install prefix matches CPU architecture (Apple Silicon: `/opt/homebrew`, Intel: `/usr/local`).
- Prevents mixed-prefix installations on migrated machines.

### 3) Brew Bundle (`Brewfile`)

Packages are declared in `Brewfile` and enforced via `brew bundle`:

**CLI tools**

- `git`: source control.
- `mise`: runtime manager for language/tool versions.
- `uv`: Python package/env tooling.
- `starship`: cross-shell prompt.
- `swiftlint`: Swift static analysis.
- `fzf`: fuzzy finder for shell/search workflows.
- `ripgrep`: fast recursive code search (`rg`).
- `bat`: file viewer with syntax highlighting.
- `eza`: modern `ls` replacement with rich output.

**Fonts**

- `font-meslo-lg-nerd-font`: patched glyph set used by `starship` and terminal icon themes.

**Applications (casks)**

- `orbstack`: local container and Linux VM runtime.
- `visual-studio-code`: editor/IDE.
- `google-chrome`: browser.
- `maccy`: clipboard history manager.
- `chatgpt`, `antigravity`, `blip`, `handy`, `logi-options+`, `rive`, `codex-app`, `copilot-cli`, `claude-code`: machine-level apps/tools intentionally pinned in setup.

**VS Code extensions**

- `github.copilot-chat`
- `google.gemini-cli-vscode-ide-companion`

### 4) Dotfiles linking

- Managed files are linked from repo to `$HOME`.
- If destination is a regular file, bootstrap moves it to `*.bak` first, then links the managed file.
- If symlink exists but points elsewhere, bootstrap re-links to repo target.
- Goal: deterministic dotfile state with safe migration.

### 5) Git Identity model

- `~/.gitconfig` stays repo-managed (shared defaults, aliases, include directives).
- Personal identity is stored in machine-local `~/.gitconfig.local` (not versioned).
- Bootstrap ensures `~/.gitconfig` includes `~/.gitconfig.local`.
- Bootstrap ensures `~/.gitconfig.local` exists.
- Bootstrap ensures `user.name` and `user.email` are present in `~/.gitconfig.local` (or placeholders are added if values cannot be resolved automatically).
- Bootstrap ensures `user.name` and `user.email` are removed from repo-managed `.gitconfig`.

### 6) mise toolchains

- Checks `mise` availability.
- Checks shims path (`~/.local/share/mise/shims`) is present in `PATH`.
- Runs `mise doctor` checks.
- Installs missing runtimes/tools declared in `.config/mise/config.toml`.

### 7) Shell configuration

- Verifies `.zshenv` (PATH dedup + mise shims) is correctly linked or equivalent.
- Ensures `.zshrc` has `eval "$(mise activate zsh)"`.
- Ensures `.zshrc` has `eval "$(starship init zsh)"`.
- Ensures `.zshrc` has `source <(fzf --zsh)` when `fzf` is installed.

### 8) macOS defaults (developer-oriented decisions)

The script enforces the following defaults:

| Area | Setting | Value | Why |
|------|---------|-------|-----|
| Keyboard | `KeyRepeat` | `2` | faster key repetition |
| Keyboard | `InitialKeyRepeat` | `15` | shorter delay before repeat starts |
| Keyboard | `ApplePressAndHoldEnabled` | `false` | enables repeat behavior instead of accent popup |
| Dock | `autohide` | `true` | maximize screen space |
| Dock | `autohide-delay` | `0` | remove dock show latency |
| Dock | `show-recents` | `false` | reduce visual noise |
| Finder | `ShowPathbar` | `true` | faster path awareness |
| Finder | `ShowStatusBar` | `true` | file/folder context visibility |
| Finder | `AppleShowAllFiles` | `true` | expose hidden files for dev workflows |
| Finder | `FXDefaultSearchScope` | `SCcf` | search current folder by default |
| Finder | `AppleShowAllExtensions` | `true` | avoid extension ambiguity |
| Screenshots | `disable-shadow` | `true` | cleaner captures |
| Screenshots | `type` | `png` | predictable lossless image format |
| Input | `NSAutomaticSpellingCorrectionEnabled` | `false` | avoid code/text mutation |
| Input | `NSAutomaticQuoteSubstitutionEnabled` | `false` | avoid smart quote corruption |
| Input | `NSAutomaticDashSubstitutionEnabled` | `false` | avoid smart dash substitution |
| System | `DSDontWriteNetworkStores` | `true` | avoid `.DS_Store` on network mounts |
| System | `DSDontWriteUSBStores` | `true` | avoid `.DS_Store` on USB volumes |

### 9) sudo authentication

Bootstrap configures this behavior:

- `pam_tid` integration in `/etc/pam.d/sudo_local` (when module exists) for biometric approval.
- If admin credentials are not cached, bootstrap requests `sudo -v` interactively in a TTY.
- In non-interactive runs, pre-cache credentials with `sudo -v` before running bootstrap.

Status is always reported in `--check` mode for PAM module presence and `sudo_local` state.

Output example:
```
── Xcode CLI Tools
  ✓  Installed at /Library/Developer/CommandLineTools

── Homebrew
  ✓  Homebrew 5.0.14 at /opt/homebrew

── Dotfiles
  ✓  ~/.zshenv
  ✓  ~/.gitconfig
  ✓  ~/.gitignore_global
  ✓  ~/.config/mise/config.toml
  ✓  ~/.config/starship.toml

── Git Identity
  ·  ~/.gitconfig includes ~/.gitconfig.local? yes
  ·  ~/.gitconfig.local has user.name? yes
  ·  ~/.gitconfig.local has user.email? yes

── mise
  ✓  mise 2026.x macos-arm64
  ✓  Shims on PATH
  ✓  mise doctor: clean
  ✓  All configured tools installed

── sudo authentication
  ·  pam_tid module present? yes
  ·  sudo_local exists? yes
  ·  sudo_local pam_tid line enabled? yes (configured)
```

## Structure

```
dotfiles/
├── bootstrap.sh             # check+apply provisioner
├── Brewfile                 # packages, casks, VS Code extensions
├── .zshenv                  # PATH dedup + mise shims (all shell contexts)
├── .gitconfig               # shared git defaults + includes ~/.gitconfig.local
├── .gitignore_global        # global ignore: .DS_Store, secrets, build artifacts
└── .config/
    ├── mise/
    │   └── config.toml      # runtimes: node, python, go, rust, ruby, dotnet
    └── starship.toml        # prompt
```

> **Note:** personal Git identity is stored in `~/.gitconfig.local` (non-versioned, machine-local).
> `bootstrap.sh` ensures `~/.gitconfig` includes it and keeps `user.name`/`user.email` out of repo-managed config.
> ```bash
> git config --file ~/.gitconfig.local user.name "Your Name"
> git config --file ~/.gitconfig.local user.email "you@example.com"
> ```

Repo-managed config files are symlinked from this repo into `$HOME`. Machine-local files (for example `~/.gitconfig.local`) stay outside the repo.

## Toolchain

Managed by [mise](https://mise.jdx.dev/). Declared in `.config/mise/config.toml`:

| Tool | Version |
|------|---------|
| Node | LTS |
| Python | 3.13 |
| Go | latest |
| Rust | latest |
| Ruby | latest |
| .NET | latest |
| Java | temurin-21 |
| Maven | 3.9 |
| pnpm | latest |
| github-cli | latest |

Java is managed via the `java` plugin with Temurin (`java = "temurin-21"`).
To customize versions, edit `.config/mise/config.toml` and run `mise install` (or `./bootstrap.sh`).

Python environments and dependencies are handled by [uv](https://docs.astral.sh/uv/).

## Customization

**Add a brew package:**
```bash
# 1. install it
brew install <package>

# 2. add to Brewfile
echo 'brew "<package>"' >> Brewfile

# 3. commit
git add Brewfile && git commit -m "feat(brew): add <package>"
```

**Add a runtime:**
```bash
# 1. edit .config/mise/config.toml
# 2. mise install
# 3. commit
```

**Add a dotfile:**
```bash
# 1. add the file to the repo
# 2. add the path to the managed=() array in bootstrap.sh
# 3. commit
```

## Maintenance

```bash
# check state anytime
./bootstrap.sh --check

# update brew packages
brew update && brew upgrade

# update runtimes
mise upgrade

# update uv itself
uv self update
```
