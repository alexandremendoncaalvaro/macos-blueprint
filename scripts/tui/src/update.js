import * as p from '@clack/prompts';
import pc from 'picocolors';
import { run, runLive } from './exec.js';
import { DOTFILES } from './config.js';

export async function updateAll() {
  p.log.step('Updating Homebrew index...');
  await runLive('brew update');

  console.log();
  p.log.step('Upgrading packages...');
  await runLive('brew upgrade');

  console.log();
  const s = p.spinner();

  s.start('Cleaning Homebrew');
  run('brew cleanup');
  s.stop('Homebrew cleaned');

  s.start('Upgrading mise tools');
  run('mise upgrade --yes 2>/dev/null || true', { timeout: 120_000 });
  s.stop('mise tools upgraded');

  s.start('Updating lockfile');
  run(`python3 "${DOTFILES}/scripts/brew-lock.py"`, { timeout: 30_000 });
  s.stop('Lockfile updated');

  s.start('Committing changes');
  const date = new Date().toISOString().split('T')[0];
  run(
    `cd "${DOTFILES}" && git add Brewfile Brewfile.lock.json 2>/dev/null; ` +
    `git diff --cached --quiet 2>/dev/null || git commit -m "chore: update packages ${date}"`,
  );
  s.stop('Changes committed');

  console.log();
  p.log.success('Everything up to date');
}
