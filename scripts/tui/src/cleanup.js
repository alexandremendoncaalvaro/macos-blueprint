import * as p from '@clack/prompts';
import pc from 'picocolors';
import { run, runLive, hasBin } from './exec.js';

export async function cleanupMenu() {
  const hasMole = hasBin('mo');

  const options = [
    { value: 'brew', label: 'Homebrew cache', hint: 'old versions and download cache' },
    { value: 'mise', label: 'mise',           hint: 'prune unused tool versions' },
  ];

  if (hasMole) {
    options.push(
      { value: 'mo-clean',     label: 'System caches',  hint: 'mo clean \u2014 logs, temp files' },
      { value: 'mo-purge',     label: 'Dev artifacts',  hint: 'mo purge \u2014 node_modules, target/, .build/' },
      { value: 'mo-installer', label: 'Old installers', hint: 'mo installer \u2014 leftover .dmg/.pkg files' },
    );
  }

  options.push(
    { value: 'derived', label: 'Xcode DerivedData', hint: 'build cache' },
  );

  const tasks = await p.multiselect({
    message: 'What to clean up?',
    options,
    required: true,
  });

  if (p.isCancel(tasks)) return;

  for (const task of tasks) {
    console.log();
    switch (task) {
      case 'brew':
        p.log.step('Cleaning Homebrew...');
        await runLive('brew cleanup --prune=all');
        break;
      case 'mise':
        p.log.step('Pruning mise...');
        await runLive('mise prune -y 2>/dev/null || true');
        break;
      case 'mo-clean':
        p.log.step('Cleaning system caches...');
        await runLive('mo clean');
        break;
      case 'mo-purge':
        p.log.step('Purging dev artifacts...');
        await runLive('mo purge');
        break;
      case 'mo-installer':
        p.log.step('Removing old installers...');
        await runLive('mo installer');
        break;
      case 'derived': {
        const dd = '/Volumes/MacMini/DerivedData';
        const s = p.spinner();
        s.start('Cleaning DerivedData');
        run(`rm -rf "${dd}"/* 2>/dev/null || true`);
        s.stop('DerivedData cleaned');
        break;
      }
    }
  }

  console.log();
  p.log.success('Cleanup complete');
}
