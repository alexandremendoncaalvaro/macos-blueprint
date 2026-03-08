import * as p from '@clack/prompts';
import pc from 'picocolors';
import { readFileSync } from 'node:fs';
import { runLive } from './exec.js';
import { DOTFILES, BREWFILE } from './config.js';

const MAC = `"${DOTFILES}/scripts/dotfiles.sh"`;

export async function packagesMenu() {
  while (true) {
    const action = await p.select({
      message: 'Package management',
      options: [
        { value: 'add',    label: 'Add',    hint: 'install and track a new package' },
        { value: 'remove', label: 'Remove', hint: 'uninstall and untrack' },
        { value: 'list',   label: 'List',   hint: 'show all tracked packages' },
        { value: 'back',   label: pc.dim('\u2190 Back') },
      ],
    });

    if (p.isCancel(action) || action === 'back') return;

    switch (action) {
      case 'add':    await addPackage(); break;
      case 'remove': await removePackage(); break;
      case 'list':   await listPackages(); break;
    }
  }
}

async function addPackage() {
  const name = await p.text({
    message: 'Package name',
    placeholder: 'e.g. ripgrep, visual-studio-code, github.copilot',
    validate: (v) => (!v.trim() ? 'Required' : undefined),
  });
  if (p.isCancel(name)) return;

  const type = await p.select({
    message: 'Type',
    options: [
      { value: '',         label: 'Auto-detect', hint: 'recommended' },
      { value: '--formula', label: 'Formula',    hint: 'CLI tool' },
      { value: '--cask',    label: 'Cask',       hint: 'GUI app' },
      { value: '--vscode',  label: 'VS Code extension' },
    ],
  });
  if (p.isCancel(type)) return;

  console.log();
  p.log.step(`Installing ${pc.cyan(name.trim())}...`);
  const code = await runLive(`${MAC} add ${name.trim()} ${type}`.trim());
  console.log();

  if (code === 0) {
    p.log.success(`${pc.cyan(name.trim())} installed and tracked`);
  } else {
    p.log.error(`Failed to install ${name.trim()}`);
  }
}

async function removePackage() {
  const packages = parseBrewfile();
  if (packages.length === 0) {
    p.log.warn('Brewfile is empty');
    return;
  }

  const selected = await p.select({
    message: 'Select package to remove',
    options: packages.map((pkg) => ({
      value: pkg.name,
      label: pkg.name,
      hint: pkg.type,
    })),
  });
  if (p.isCancel(selected)) return;

  const ok = await p.confirm({
    message: `Remove ${pc.red(selected)}?`,
  });
  if (p.isCancel(ok) || !ok) return;

  console.log();
  p.log.step(`Removing ${pc.red(selected)}...`);
  const code = await runLive(`${MAC} remove ${selected}`);
  console.log();

  if (code === 0) {
    p.log.success(`${pc.red(selected)} removed`);
  } else {
    p.log.error(`Failed to remove ${selected}`);
  }
}

async function listPackages() {
  console.log();
  await runLive(`${MAC} list`);
  console.log();
}

function parseBrewfile() {
  try {
    const content = readFileSync(BREWFILE, 'utf-8');
    const packages = [];
    for (const line of content.split('\n')) {
      const match = line.match(/^(brew|cask|vscode)\s+"([^"]+)"/);
      if (match) {
        packages.push({ type: match[1], name: match[2] });
      }
    }
    return packages;
  } catch {
    return [];
  }
}
