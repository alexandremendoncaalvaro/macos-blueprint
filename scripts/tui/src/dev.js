import * as p from '@clack/prompts';
import pc from 'picocolors';
import { execSync } from 'node:child_process';
import { runLive, hasBin } from './exec.js';
import { DOTFILES } from './config.js';

const DEV = `"${DOTFILES}/scripts/dev.sh"`;

const STACKS = ['python', 'node', 'go', 'rust', 'csharp', 'java'];

export async function devMenu() {
  while (true) {
    const action = await p.select({
      message: 'Devcontainers',
      options: [
        { value: 'create',       label: 'Create',         hint: 'scaffold .devcontainer/ from templates' },
        { value: 'list',         label: 'List',           hint: 'find devcontainers in your projects' },
        { value: 'open',         label: 'Open',           hint: 'launch VSCode + reopen in container' },
        { value: 'mount-claude', label: 'Mount Claude',   hint: 'add ~/.claude bind mount to current project' },
        { value: 'sync-ext',     label: 'Sync extensions', hint: 'push Brewfile vscode entries to defaultExtensions' },
        { value: 'doctor',       label: 'Doctor',         hint: 'diagnose host auth + tools' },
        { value: 'back',         label: pc.dim('← Back') },
      ],
    });

    if (p.isCancel(action) || action === 'back') return;

    switch (action) {
      case 'create':       await createDev(); break;
      case 'list':         await runLive(`${DEV} list`); break;
      case 'open':         await openDev(); break;
      case 'mount-claude': await runLive(`${DEV} mount-claude`); break;
      case 'sync-ext':     await runLive(`${DEV} sync-ext`); break;
      case 'doctor':       console.log(); await runLive(`${DEV} doctor`); break;
    }
    console.log();
  }
}

async function createDev() {
  const name = await p.text({
    message: 'Project name',
    placeholder: 'e.g. api, ml-pipeline, web',
    validate: (v) => (!v.trim() ? 'Required' : /[^a-zA-Z0-9._-]/.test(v) ? 'Only [a-zA-Z0-9._-]' : undefined),
  });
  if (p.isCancel(name)) return;

  const stack = await p.select({
    message: 'Stack',
    options: STACKS.map((s) => ({ value: s, label: s })),
  });
  if (p.isCancel(stack)) return;

  const flavorList = listFlavors(stack);
  let flavors = [];
  if (flavorList.length > 0) {
    const picked = await p.multiselect({
      message: 'Flavors (optional)',
      options: flavorList.map((f) => ({ value: f, label: f })),
      required: false,
    });
    if (p.isCancel(picked)) return;
    flavors = picked || [];
  }

  const where = await p.text({
    message: 'Target directory',
    placeholder: `${process.cwd()}/${name.trim()}`,
    initialValue: `${process.cwd()}/${name.trim()}`,
  });
  if (p.isCancel(where)) return;

  const flavorArgs = flavors.map((f) => `--${f}`).join(' ');
  const cmd = `${DEV} create ${name.trim()} --${stack} ${flavorArgs} --in "${where}"`;

  console.log();
  const code = await runLive(cmd);
  console.log();

  if (code === 0) {
    p.log.success(`Created ${pc.cyan(where)}`);
    const open = await p.confirm({ message: 'Open in VSCode now?' });
    if (!p.isCancel(open) && open) {
      if (hasBin('code')) {
        await runLive(`code "${where}"`);
        p.log.info('Cmd+Shift+P → Dev Containers: Reopen in Container');
      } else {
        p.log.warn('VSCode \'code\' CLI not on PATH');
      }
    }
  } else {
    p.log.error('Create failed');
  }
}

async function openDev() {
  const dir = await p.text({
    message: 'Project path',
    placeholder: process.cwd(),
    initialValue: process.cwd(),
  });
  if (p.isCancel(dir)) return;
  await runLive(`${DEV} open "${dir}"`);
}

function listFlavors(stack) {
  try {
    const out = execSync(`${DEV} flavors ${stack}`, { encoding: 'utf-8' });
    return out
      .split('\n')
      .slice(1)
      .map((l) => l.trim())
      .filter(Boolean);
  } catch {
    return [];
  }
}
