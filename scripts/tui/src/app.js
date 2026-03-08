#!/usr/bin/env node

import * as p from '@clack/prompts';
import pc from 'picocolors';
import { showQuickStatus } from './status.js';
import { packagesMenu } from './packages.js';
import { cleanupMenu } from './cleanup.js';
import { updateAll } from './update.js';
import { run, runLive, hasBin } from './exec.js';
import { DOTFILES } from './config.js';

async function main() {
  console.clear();
  p.intro(`${pc.bgCyan(pc.black(' mac '))} ${pc.dim('macOS system manager')}`);

  await showQuickStatus();

  while (true) {
    const action = await p.select({
      message: 'What would you like to do?',
      options: [
        { value: 'packages',  label: 'Packages',      hint: 'add, remove, list' },
        { value: 'update',    label: 'Update',         hint: 'upgrade everything' },
        { value: 'cleanup',   label: 'Cleanup',        hint: 'free disk space' },
        { value: 'disk',      label: 'Disk',           hint: 'analyze usage' },
        { value: 'uninstall', label: 'Uninstall',      hint: 'remove app + leftovers' },
        { value: 'status',    label: 'Health Check',   hint: 'full diagnostic' },
        { value: 'sync',      label: 'Sync',           hint: 'apply bootstrap fixes' },
        { value: 'push',      label: 'Push',           hint: 'push dotfiles to remote' },
        { value: 'exit',      label: pc.dim('Exit') },
      ],
    });

    if (p.isCancel(action) || action === 'exit') break;

    switch (action) {
      case 'packages':
        await packagesMenu();
        break;

      case 'update':
        await updateAll();
        break;

      case 'cleanup':
        await cleanupMenu();
        break;

      case 'disk':
        if (!hasBin('mo')) {
          p.log.warn('mole (mo) not installed \u2014 run: brew install mole');
          break;
        }
        await runLive('mo analyze');
        break;

      case 'uninstall':
        if (!hasBin('mo')) {
          p.log.warn('mole (mo) not installed \u2014 run: brew install mole');
          break;
        }
        await runLive('mo uninstall');
        break;

      case 'status':
        console.log();
        await runLive(`"${DOTFILES}/bootstrap.sh" --check`);
        console.log();
        break;

      case 'sync': {
        const ok = await p.confirm({ message: 'Apply all bootstrap fixes?' });
        if (p.isCancel(ok) || !ok) break;
        console.log();
        await runLive(`"${DOTFILES}/bootstrap.sh"`);
        console.log();
        break;
      }

      case 'push': {
        const s = p.spinner();
        s.start('Pushing to remote');
        const out = run(`cd "${DOTFILES}" && git push 2>&1`, { timeout: 30_000 });
        s.stop('Pushed');
        if (out) p.log.info(out);
        break;
      }
    }
  }

  p.outro(pc.dim('Done'));
}

main().catch((err) => {
  p.log.error(err.message);
  process.exit(1);
});
