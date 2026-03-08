import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));

export const DOTFILES = resolve(__dirname, '..', '..', '..');
export const BREWFILE = resolve(DOTFILES, 'Brewfile');
export const SCRIPTS = resolve(DOTFILES, 'scripts');
