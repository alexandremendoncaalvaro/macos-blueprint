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
- Install TUI dependencies (Node.js via mise, `@clack/prompts`).
- Configure shell integration (`mise`, `starship`, `fzf`).
- Apply macOS developer defaults.
- Offload user folders and dev tool data to external SSD (`/Volumes/MacMini`).
- Configure `sudo` Touch ID (`pam_tid`) when available.
- Weekly drift detection with macOS notification.
- Configure SSH agent + GitHub host block so devcontainers can forward `SSH_AUTH_SOCK`.
- Generate per-project devcontainers (`mac dev`) from layered, tested templates.

## Quick start

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

## The `mac` CLI

After bootstrap, the `mac` command (alias for `scripts/dotfiles.sh`) is available in every shell.

### Interactive TUI

Run `mac` with no arguments to open the interactive terminal interface:

```bash
mac
```

The TUI uses `@clack/prompts` (Node.js) and shows a quick status dashboard on launch, then a menu for all operations. Sub-menus group related actions (e.g. Packages > Add / Remove / List).

Built with the existing stack — Node 22 is already managed by mise, so the only extra dependencies are `@clack/prompts` and `picocolors` (4 npm packages total).

### Direct commands

All commands also work non-interactively for scripting and quick one-offs:

```bash
# Package management
mac add <name> [--cask|--formula|--vscode]   # install and track
mac remove <name>                            # uninstall and untrack
mac list                                     # show tracked packages
mac update                                   # upgrade all + commit lockfile

# System
mac status                                   # quick health check
mac check                                    # full diagnostic (no changes)
mac sync                                     # apply all bootstrap fixes
mac cleanup                                  # brew + mise + mole clean
mac disk                                     # analyze disk usage (mole)
mac uninstall [app]                          # remove app + leftover files (mole)

# Repo
mac lock                                     # regenerate Brewfile.lock.json
mac push                                     # push dotfiles to remote

# Devcontainers
mac dev create <name> --<stack> [--<flavor>...]   # new project from templates
mac dev init   --<stack> [--<flavor>...]          # add devcontainer to existing project
mac dev validate [path]                            # schema-ish + mounts + scripts checks
mac dev diff [path]                                # drift vs current template
mac dev upgrade [path]                             # regenerate from saved metadata
mac dev rebuild | clean [path]                     # devcontainer rebuild / remove
mac dev list | open | doctor | sync-ext            # discover / health
mac dev stacks | flavors <stack> | test            # help / regression suite
```

### Mole integration

[mole](https://github.com/nicholasgasior/mole) (`mo`) is a Go CLI for macOS maintenance. The `mac` CLI integrates it where it makes sense:

| `mac` command | What runs | Purpose |
|---------------|-----------|---------|
| `mac cleanup` | `brew cleanup` + `mise prune` + `mo clean` | Free space from caches, logs, temp files |
| `mac disk` | `mo analyze` | Interactive disk usage explorer |
| `mac uninstall` | `mo uninstall` | Remove apps with leftover files |

The TUI cleanup menu also offers `mo purge` (node_modules, target/, .build/) and `mo installer` (old .dmg/.pkg) as selectable options.

> Touch ID for sudo is handled by bootstrap step 10, not duplicated from mole.

## Devcontainers (`mac dev`)

`mac dev` scaffolds VSCode devcontainers from layered templates so a new project gets a working container without copy-pasting JSON. Templates live in `templates/devcontainers/` and merge in three tiers:

```
templates/devcontainers/
├── _base/                    # mounts, post-create runner, core extensions
├── stacks/<stack>.json       # image + features + extensions for a language
└── flavors/<stack>-<f>.json  # overlay (e.g. python-fastapi adds port 8000)
```

The merge uses `jq *` for objects and explicit dedup for the array fields (`mounts`, `forwardPorts`, `customizations.vscode.extensions`). Each layer can ship a sibling `.post.sh` that gets copied into `.devcontainer/post-create.d/` and run by `post-create.sh` in lexical order. `create` writes `.devcontainer/.mac-dev.json` so `upgrade`/`diff` can round-trip.

### Stacks and flavors

| Stack | Image | Flavors |
|-------|-------|---------|
| `python` | `mcr.microsoft.com/devcontainers/python:3-3.13-trixie` (uv pre-installed) | `vanilla`, `fastapi`, `notebooks`, `opencv`, `pytorch`, `tensorflow` |
| `node` | `javascript-node:1-22-bookworm` | `vite-ts`, `vite-js`, `astro`, `react` |
| `cpp` | `cpp:1-debian-12` (cmake + ninja + vcpkg pre-baked) | — (CMake 3.28 + C++20 + Catch2 scaffold from `cpp.post.sh`) |
| `go` | `go:1-1.23-bookworm` | — |
| `rust` | `rust:1-1-bookworm` | — |
| `csharp` | `dotnet:1-9.0-bookworm` | — |
| `java` | `java:1-21-bookworm` (Maven + Gradle) | — |

### Examples

```bash
# new FastAPI service
mac dev create api --python --fastapi
cd api && code .  # then: Cmd+Shift+P → Reopen in Container

# ML notebook + pytorch in current dir
cd existing-project && mac dev init --python --notebooks --pytorch

# health check before sharing the project
mac dev validate

# templates updated upstream → preview, then apply
mac dev diff
mac dev upgrade
```

### Host bind mounts (auto-wired by `_base`)

Each generated container mounts three host paths. Without these, the container fails to start:

| Source | Purpose |
|--------|---------|
| `~/.gitconfig.local` | git identity (read-only) |
| `~/.claude` | claude-code login persists across containers |
| `~/.ssh` | SSH keys (copied + chmod inside `00-base.sh`); requires loaded ssh-agent on host (configured by step 5b) |

`mac dev doctor` surfaces what's missing on the host before you build.

### Tests + CI

Bats covers the dev subsystem:

```bash
mac dev test              # runs tests/dev/ (68 tests, ~5s)
UPDATE_SNAPSHOTS=1 mac dev test tests/dev/snapshot.bats   # accept new shape
```

`.github/workflows/dev-tests.yml` runs the suite on macOS and `shellcheck` on Linux for every push touching `bootstrap.sh`, `scripts/*.sh`, `templates/devcontainers/**`, or `tests/dev/**`. `.shellcheckrc` documents the rationale for each disabled rule.

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
- `ffmpeg`: video/audio processing.
- `mole`: macOS maintenance CLI (cleanup, disk analysis, app removal).

**Fonts**

- `font-meslo-lg-nerd-font`: patched glyph set used by `starship` and terminal icon themes.

**Applications (casks)**

- `orbstack`: local container and Linux VM runtime.
- `visual-studio-code`: editor/IDE.
- `google-chrome`: browser.
- `maccy`: clipboard history manager.
- `tailscale-app`: VPN / mesh networking.
- `chatgpt`, `antigravity`, `blip`, `logi-options+`, `rive`, `codex-app`, `copilot-cli`, `claude-code`: machine-level apps/tools intentionally pinned in setup.

**VS Code extensions**

- `anthropic.claude-code`
- `github.copilot-chat`
- `github.vscode-github-actions`
- `google.gemini-cli-vscode-ide-companion`
- `ms-azuretools.vscode-containers`
- `ms-vscode-remote.remote-containers`, `remote-ssh`, `remote-ssh-edit`, `remote-explorer`

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

### 5b) SSH (devcontainer agent forwarding)

VSCode Dev Containers forward `$SSH_AUTH_SOCK` from the host. If the host agent is empty (default after every reboot), git over SSH inside containers fails. This step:

- Detects the first available key (`id_ed25519` preferred, `id_rsa` fallback). Does **not** generate one — surfaces a hint if absent.
- Ensures `~/.ssh/config` has a `Host github.com` block with `AddKeysToAgent yes` / `UseKeychain yes` / `IdentityFile <key>` / `IdentitiesOnly yes`. After this, the agent populates lazily on first SSH after each reboot.
- Loads the key into the running agent now via `ssh-add --apple-use-keychain`, falling back to plain `ssh-add`.

All operations are idempotent and respect `--check`.

### 6) mise toolchains

- Checks `mise` availability.
- Checks shims path (`~/.local/share/mise/shims`) is present in `PATH`.
- Runs `mise doctor` checks.
- Installs missing runtimes/tools declared in `.config/mise/config.toml`.

### 6b) TUI dependencies

- Checks `scripts/tui/node_modules` exists.
- Runs `npm install --production` if missing (requires Node from mise).
- Lightweight: only `@clack/prompts` + `picocolors` (4 packages total).

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

### 9) External SSD storage (MacMini)

Offloads user folders and dev tool data to an external NVMe SSD at `/Volumes/MacMini`.

**Skipped entirely when the volume is not mounted** — safe to run on machines without the SSD.

| What | Internal path | External target |
|------|---------------|-----------------|
| Dev, Documents, Downloads, Desktop, Pictures, Movies, Music | `~/` | `/Volumes/MacMini/Home/` |
| Homebrew cache | `~/Library/Caches/Homebrew` | `/Volumes/MacMini/Homebrew/Cache` |
| Playwright browsers | `~/.cache/ms-playwright` | `/Volumes/MacMini/playwright` |
| mise installs | `~/.local/share/mise` | `/Volumes/MacMini/mise` |
| Rust toolchains | `~/.rustup` | `/Volumes/MacMini/rustup` |
| Cargo | `~/.cargo` | `/Volumes/MacMini/cargo` |
| npm cache | `~/.npm` | `/Volumes/MacMini/npm-cache` |
| pnpm store | (default) | `/Volumes/MacMini/pnpm-store` |
| Xcode DerivedData | `~/Library/Developer/Xcode/DerivedData` | `/Volumes/MacMini/DerivedData` |

Environment variables are set in `.zshenv` so they apply in all shell contexts.
Home folder migration is fully automatic: bootstrap syncs local contents to the SSD via `rsync`, removes the local directory with `sudo`, and creates the symlink. On a fresh install where the SSD already has the data, the rsync is a no-op and only the symlink is created.

### 10) sudo authentication

Bootstrap configures this behavior:

- `pam_tid` integration in `/etc/pam.d/sudo_local` (when module exists) for biometric approval.
- If admin credentials are not cached, bootstrap requests `sudo -v` interactively in a TTY.
- In non-interactive runs, pre-cache credentials with `sudo -v` before running bootstrap.

Status is always reported in `--check` mode for PAM module presence and `sudo_local` state.

### 11) Drift check

A launchd agent runs `bootstrap.sh --check` every Monday at 10:00 and sends a macOS notification if drift is detected.

## Structure

```
dotfiles/
├── bootstrap.sh                 # check+apply provisioner (12 steps)
├── Brewfile                     # packages, casks, VS Code extensions
├── Brewfile.lock.json           # exact installed versions (auto-generated)
├── .zshenv                      # PATH dedup + mise shims + SSD env vars
├── .gitconfig                   # shared git defaults + includes ~/.gitconfig.local
├── .gitignore_global            # global ignore: .DS_Store, secrets, build artifacts
├── .shellcheckrc                # rationale-driven shellcheck disables
├── .config/
│   ├── mise/
│   │   └── config.toml          # runtimes: node, python, go, rust, ruby, dotnet, java
│   └── starship.toml            # prompt theme
├── scripts/
│   ├── dotfiles.sh              # mac CLI entry point (alias: mac)
│   ├── dev.sh                   # `mac dev` subsystem (devcontainer scaffolding)
│   ├── brew-lock.py             # generates Brewfile.lock.json
│   ├── drift-check.sh           # weekly drift detection + notification
│   ├── com.dotfiles.drift-check.plist  # launchd agent definition
│   └── tui/                     # interactive terminal UI
│       ├── package.json         # @clack/prompts + picocolors
│       └── src/
│           ├── app.js           # main menu loop
│           ├── config.js        # paths (DOTFILES, BREWFILE)
│           ├── exec.js          # shell helpers (run, runAsync, runLive)
│           ├── status.js        # quick status dashboard
│           ├── packages.js      # add / remove / list sub-menu
│           ├── dev.js           # mac dev menu (create/init/validate/...)
│           ├── cleanup.js       # cleanup with mole integration
│           └── update.js        # upgrade all + lockfile + commit
├── templates/
│   └── devcontainers/           # layered devcontainer templates
│       ├── _base/               # name placeholder, mounts, post-create runner
│       ├── stacks/              # python|node|go|rust|cpp|csharp|java
│       └── flavors/             # python-fastapi, node-vite-ts, ...
├── tests/
│   └── dev/                     # bats test suite (68 tests + JSON snapshots)
└── .github/
    └── workflows/
        └── dev-tests.yml        # CI: shellcheck (ubuntu) + bats (macos)
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
| Node | 22 |
| Python | 3.13 |
| Go | latest |
| Rust | latest |
| Ruby | latest |
| .NET | latest |
| Java | temurin-21 |
| Maven | 3.9 |
| pnpm | latest |
| GitHub CLI | latest |
| Gemini CLI | latest (npm) |
| Codex CLI | latest (npm) |

Java is managed via the `java` plugin with Temurin (`java = "temurin-21"`).
To customize versions, edit `.config/mise/config.toml` and run `mise install` (or `./bootstrap.sh`).

Python environments and dependencies are handled by [uv](https://docs.astral.sh/uv/).

## Customization

**Add a package (recommended: use `mac` CLI):**
```bash
mac add ripgrep              # auto-detects type
mac add visual-studio-code   # auto-detects as cask
mac add github.copilot --vscode  # explicit type
```

**Add a package (manual):**
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
# interactive — opens TUI with status dashboard
mac

# check state anytime
mac check

# upgrade everything (brew + mise + lockfile + auto-commit)
mac update

# free disk space (brew + mise + mole)
mac cleanup

# analyze disk usage
mac disk

# update runtimes only
mise upgrade

# update uv itself
uv self update
```
