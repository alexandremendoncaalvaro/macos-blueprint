import * as p from '@clack/prompts';
import pc from 'picocolors';
import { execSync } from 'node:child_process';
import { runLive, hasBin } from './exec.js';
import { DOTFILES } from './config.js';

const DEV = `"${DOTFILES}/scripts/dev.sh"`;
const STACKS = ['python', 'node', 'go', 'rust', 'cpp', 'csharp', 'java'];

export async function devMenu() {
  while (true) {
    const action = await p.select({
      message: 'Devcontainers',
      options: [
        { value: 'create',       label: 'Create',         hint: 'new project — scaffold from templates' },
        { value: 'init',         label: 'Init',           hint: 'add devcontainer to existing project' },
        { value: 'list',         label: 'List',           hint: 'find devcontainers in your projects' },
        { value: 'open',         label: 'Open',           hint: 'launch VSCode + reopen in container' },
        { value: 'validate',     label: 'Validate',       hint: 'check schema, mounts, scripts, image' },
        { value: 'diff',         label: 'Diff',           hint: 'show drift vs current template' },
        { value: 'upgrade',      label: 'Upgrade',        hint: 'regenerate from saved metadata' },
        { value: 'rebuild',      label: 'Rebuild',        hint: 'devcontainer CLI rebuild (no-cache)' },
        { value: 'clean',        label: 'Clean',          hint: 'remove .devcontainer/' },
        { value: 'mount-claude', label: 'Mount Claude',   hint: 'add ~/.claude bind mount to current project' },
        { value: 'sync-ext',     label: 'Sync extensions', hint: 'push Brewfile vscode entries to defaultExtensions' },
        { value: 'doctor',       label: 'Doctor',         hint: 'diagnose host auth + tools' },
        { value: 'test',         label: 'Run tests',      hint: 'bats — guardrail against regressions' },
        { value: 'back',         label: pc.dim('← Back') },
      ],
    });

    if (p.isCancel(action) || action === 'back') return;

    console.log();
    switch (action) {
      case 'create':       await createDev(); break;
      case 'init':         await initDev(); break;
      case 'list':         await runLive(`${DEV} list`); break;
      case 'open':         await pickPathAndRun('open'); break;
      case 'validate':     await pickPathAndRun('validate'); break;
      case 'diff':         await pickPathAndRun('diff'); break;
      case 'upgrade':      await pickPathAndRun('upgrade'); break;
      case 'rebuild':      await pickPathAndRun('rebuild'); break;
      case 'clean':        await cleanDev(); break;
      case 'mount-claude': await runLive(`${DEV} mount-claude`); break;
      case 'sync-ext':     await runLive(`${DEV} sync-ext`); break;
      case 'doctor':       await runLive(`${DEV} doctor`); break;
      case 'test':         await runLive(`${DEV} test`); break;
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

  const stack = await pickStack();
  if (!stack) return;

  const flavors = await pickFlavors(stack);
  if (flavors === null) return;

  const where = await p.text({
    message: 'Target directory',
    placeholder: `${process.cwd()}/${name.trim()}`,
    initialValue: `${process.cwd()}/${name.trim()}`,
  });
  if (p.isCancel(where)) return;

  const flavorArgs = flavors.map((f) => `--${f}`).join(' ');
  const code = await runLive(`${DEV} create ${name.trim()} --${stack} ${flavorArgs} --in "${where}"`);

  if (code === 0) {
    p.log.success(`Created ${pc.cyan(where)}`);
    await maybeOpen(where);
  } else {
    p.log.error('Create failed');
  }
}

async function initDev() {
  const target = await p.text({
    message: 'Target project directory',
    placeholder: process.cwd(),
    initialValue: process.cwd(),
  });
  if (p.isCancel(target)) return;

  const stack = await pickStack();
  if (!stack) return;

  const flavors = await pickFlavors(stack);
  if (flavors === null) return;

  const flavorArgs = flavors.map((f) => `--${f}`).join(' ');
  const code = await runLive(`${DEV} init --${stack} ${flavorArgs} --in "${target}"`);

  if (code === 0) {
    p.log.success(`Initialized devcontainer in ${pc.cyan(target)}`);
    await maybeOpen(target);
  } else {
    p.log.error('Init failed');
  }
}

async function cleanDev() {
  const dir = await p.text({
    message: 'Project to clean',
    placeholder: process.cwd(),
    initialValue: process.cwd(),
  });
  if (p.isCancel(dir)) return;
  const ok = await p.confirm({ message: `Remove ${dir}/.devcontainer/ ?`, initialValue: false });
  if (p.isCancel(ok) || !ok) return;
  await runLive(`${DEV} clean "${dir}" --force`);
}

async function pickPathAndRun(sub) {
  const dir = await p.text({
    message: 'Project path',
    placeholder: process.cwd(),
    initialValue: process.cwd(),
  });
  if (p.isCancel(dir)) return;
  await runLive(`${DEV} ${sub} "${dir}"`);
}

async function pickStack() {
  const stack = await p.select({
    message: 'Stack',
    options: STACKS.map((s) => ({ value: s, label: s })),
  });
  return p.isCancel(stack) ? null : stack;
}

async function pickFlavors(stack) {
  const flavorList = listFlavors(stack);
  if (flavorList.length === 0) return [];
  const picked = await p.multiselect({
    message: 'Flavors (optional)',
    options: flavorList.map((f) => ({ value: f, label: f })),
    required: false,
  });
  if (p.isCancel(picked)) return null;
  return picked || [];
}

async function maybeOpen(where) {
  const open = await p.confirm({ message: 'Open in VSCode now?' });
  if (p.isCancel(open) || !open) return;
  if (!hasBin('code')) {
    p.log.warn(`VSCode 'code' CLI not on PATH`);
    return;
  }
  await runLive(`code "${where}"`);
  p.log.info('Cmd+Shift+P → Dev Containers: Reopen in Container');
}

function listFlavors(stack) {
  try {
    const out = execSync(`${DEV} flavors ${stack}`, { encoding: 'utf-8' });
    return out
      .split('\n')
      .slice(1)
      .map((l) => l.replace(/\x1b\[[0-9;]*m/g, '').trim())
      .filter(Boolean);
  } catch {
    return [];
  }
}
