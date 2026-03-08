import { execSync, spawn, exec } from 'node:child_process';
import { promisify } from 'node:util';

const execPromise = promisify(exec);

/** Run a command synchronously and return trimmed stdout. */
export function run(cmd, opts = {}) {
  try {
    return execSync(cmd, {
      encoding: 'utf-8',
      timeout: opts.timeout ?? 30_000,
      stdio: ['pipe', 'pipe', 'pipe'],
    }).trim();
  } catch (e) {
    if (opts.throws) throw e;
    return e.stdout?.trim?.() ?? '';
  }
}

/** Run a command asynchronously (non-blocking — allows spinners to animate). */
export async function runAsync(cmd, timeout = 15_000) {
  try {
    const { stdout } = await execPromise(cmd, { timeout, encoding: 'utf-8' });
    return stdout.trim();
  } catch (e) {
    return e.stdout?.trim?.() ?? '';
  }
}

/** Spawn a command with inherited stdio (for interactive / streaming output). */
export function runLive(cmd) {
  return new Promise((resolve) => {
    const child = spawn(cmd, { stdio: 'inherit', shell: true });
    child.on('close', (code) => resolve(code ?? 0));
    child.on('error', () => resolve(1));
  });
}

/** Check if a binary is available on PATH. */
export function hasBin(name) {
  try {
    execSync(`command -v ${name}`, { stdio: 'pipe' });
    return true;
  } catch {
    return false;
  }
}
