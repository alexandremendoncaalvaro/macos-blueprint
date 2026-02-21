# macos-blueprint

Declarative macOS development environment. Checks the state of every component before acting — safe to run on a fresh machine or an existing one.

## Philosophy

```
Host        → stable, minimal
Toolchains  → managed by mise
Dependencies → per-project
Services    → containers (OrbStack)
```

No global dependency pollution. No manual steps. No guessing what's installed.

## Usage

**Fresh machine** — clone and run:
```bash
git clone https://github.com/alexandremendoncaalvaro/macos-blueprint ~/dotfiles
cd ~/dotfiles && ./bootstrap.sh
```

**Existing machine** — diagnose without changing anything:
```bash
./bootstrap.sh --check
```

**Apply fixes:**
```bash
./bootstrap.sh
```

## What it does

The script checks each component in order, reports its state, and fixes only what needs fixing.

| Step | Checks |
|------|--------|
| Xcode CLI Tools | installed, required by Homebrew and git |
| Homebrew | installed, correct architecture prefix |
| Brew bundle | all packages from `Brewfile` satisfied |
| Dotfiles | each file symlinked, pointing to correct source |
| mise | installed, shims on PATH, doctor clean, all tools present |
| Shell | `.zshrc` has `mise activate` + `starship init`, `.zshenv` correct |
| macOS defaults | keyboard, dock, Finder, screenshot preferences |

Output example:
```
── Xcode CLI Tools
  ✓  Installed at /Library/Developer/CommandLineTools

── Homebrew
  ✓  Homebrew 5.0.14 at /opt/homebrew

── Dotfiles
  ✓  ~/.zshenv
  ✓  ~/.config/mise/config.toml
  ✓  ~/.config/starship.toml

── mise
  ✓  mise 2026.x macos-arm64
  ✓  Shims on PATH
  ✓  mise doctor: clean
  ✓  All configured tools installed
```

## Structure

```
dotfiles/
├── bootstrap.sh             # check+apply provisioner
├── Brewfile                 # packages, casks, VS Code extensions
├── .zshenv                  # PATH dedup + mise shims (all shell contexts)
└── .config/
    ├── mise/
    │   └── config.toml      # runtimes: node, python, go, rust, ruby, dotnet
    └── starship.toml        # prompt
```

All config files are symlinked from this repo into `$HOME`. Edit here, changes take effect immediately.

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
| pnpm | latest |
| github-cli | latest |

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
