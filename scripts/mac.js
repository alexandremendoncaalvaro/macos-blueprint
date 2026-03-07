const completionSpec = {
  name: "mac",
  description: "Manage macOS system state via dotfiles",
  subcommands: [
    {
      name: "add",
      description: "Install a package and track it in Brewfile",
      args: {
        name: "name",
        description: "Package, cask, or VS Code extension name",
        generators: {
          script: ["bash", "-c", "brew formulae 2>/dev/null; brew casks 2>/dev/null"],
          postProcess: (output) =>
            output
              .split("\n")
              .filter(Boolean)
              .map((name) => ({ name, icon: "📦" })),
        },
      },
      options: [
        { name: "--cask", description: "Force install as Homebrew cask" },
        { name: "--formula", description: "Force install as Homebrew formula" },
        { name: "--vscode", description: "Force install as VS Code extension" },
      ],
    },
    {
      name: "remove",
      description: "Uninstall a package and remove from Brewfile",
      args: {
        name: "name",
        description: "Package to remove",
        generators: {
          script: [
            "bash",
            "-c",
            "grep -E '^(brew|cask|vscode) \"' ~/dotfiles/Brewfile 2>/dev/null | sed 's/.*\"\\(.*\\)\".*/\\1/'",
          ],
          postProcess: (output) =>
            output
              .split("\n")
              .filter(Boolean)
              .map((name) => ({ name, icon: "🗑️" })),
        },
      },
    },
    {
      name: "list",
      description: "Show all tracked packages with versions",
    },
    {
      name: "status",
      description: "Quick health check (disk, brew, mise, repo, drift)",
    },
    {
      name: "check",
      description: "Full diagnostic via bootstrap --check (no changes)",
    },
    {
      name: "sync",
      description: "Apply all fixes via bootstrap",
    },
    {
      name: "update",
      description: "Upgrade all packages and commit lockfile",
    },
    {
      name: "cleanup",
      description: "Remove old caches, unused packages, DerivedData",
    },
    {
      name: "lock",
      description: "Regenerate Brewfile.lock.json",
    },
    {
      name: "push",
      description: "Push dotfiles repo to remote",
    },
  ],
};

module.exports = completionSpec;
