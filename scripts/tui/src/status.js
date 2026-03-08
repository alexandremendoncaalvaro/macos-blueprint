import * as p from '@clack/prompts';
import pc from 'picocolors';
import { runAsync } from './exec.js';
import { DOTFILES } from './config.js';

export async function showQuickStatus() {
  const s = p.spinner();
  s.start('Reading system status');

  const [disk, brew, mise, repo] = await Promise.all([
    getDisk(),
    getBrewOutdated(),
    getMiseStatus(),
    getRepoStatus(),
  ]);

  s.stop('System overview');

  const w = 10;
  p.note(
    [
      `${pc.bold('Disk'.padEnd(w))} ${disk}`,
      `${pc.bold('Brew'.padEnd(w))} ${brew}`,
      `${pc.bold('mise'.padEnd(w))} ${mise}`,
      `${pc.bold('Repo'.padEnd(w))} ${repo}`,
    ].join('\n'),
  );
}

async function getDisk() {
  const [internal, external] = await Promise.all([
    runAsync("df -h / | awk 'NR==2{print $4}'"),
    runAsync("df -h /Volumes/MacMini 2>/dev/null | awk 'NR==2{print $4}'"),
  ]);

  let result = `${internal || '?'} free`;
  if (external) {
    result += `  ${pc.dim('·')}  ${external} free ${pc.dim('(SSD)')}`;
  }
  return result;
}

async function getBrewOutdated() {
  const raw = await runAsync('brew outdated --quiet 2>/dev/null | wc -l');
  const n = parseInt(raw) || 0;
  return n === 0 ? pc.green('up to date') : pc.yellow(`${n} outdated`);
}

async function getMiseStatus() {
  const raw = await runAsync('mise ls --missing 2>/dev/null | wc -l');
  const n = parseInt(raw) || 0;
  return n === 0 ? pc.green('all installed') : pc.yellow(`${n} missing`);
}

async function getRepoStatus() {
  const [dirtyRaw, aheadRaw] = await Promise.all([
    runAsync(`cd "${DOTFILES}" && git status --porcelain 2>/dev/null | wc -l`),
    runAsync(`cd "${DOTFILES}" && git rev-list --count @{u}..HEAD 2>/dev/null`),
  ]);

  const dirty = parseInt(dirtyRaw) || 0;
  const ahead = parseInt(aheadRaw) || 0;
  const parts = [];

  parts.push(dirty === 0 ? pc.green('clean') : pc.yellow(`${dirty} uncommitted`));
  if (ahead > 0) parts.push(pc.yellow(`${ahead} unpushed`));

  return parts.join(`  ${pc.dim('·')}  `);
}
