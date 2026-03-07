#!/usr/bin/env python3
"""Generate Brewfile.lock.json with exact installed versions."""
import json
import subprocess
import datetime
import sys
from pathlib import Path


def get_versions(cmd):
    result = subprocess.run(cmd, capture_output=True, text=True)
    versions = {}
    for line in result.stdout.strip().split("\n"):
        if line:
            parts = line.split()
            versions[parts[0]] = parts[1] if len(parts) > 1 else ""
    return dict(sorted(versions.items()))


def main():
    lock = {
        "generated": datetime.datetime.now(datetime.timezone.utc).strftime(
            "%Y-%m-%dT%H:%M:%SZ"
        ),
        "formulae": get_versions(["brew", "list", "--formula", "--versions"]),
        "casks": get_versions(["brew", "list", "--cask", "--versions"]),
    }

    dotfiles = Path(__file__).resolve().parent.parent
    lockfile = dotfiles / "Brewfile.lock.json"
    lockfile.write_text(json.dumps(lock, indent=2) + "\n")
    print(f"Written {lockfile}")


if __name__ == "__main__":
    main()
