import { readFileSync, existsSync, mkdirSync, writeFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { randomBytes } from 'node:crypto';

export const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
export const dataDir = resolve(process.env.MY_STOCK_DATA_DIR ?? `${root}/.local`);
mkdirSync(dataDir, { recursive: true, mode: 0o700 });

function selectedValues(paths) {
  const values = {};
  for (const path of paths) {
    if (!existsSync(path)) continue;
    for (const line of readFileSync(path, 'utf8').split(/\r?\n/)) {
      const match = line.match(/^\s*(?:export\s+)?(SLACK_BOT_TOKEN|SLACK_CHANNEL_ID)\s*=\s*(.*?)\s*$/);
      if (match) values[match[1]] = match[2].replace(/^["']|["']$/g, '');
    }
  }
  return values;
}

export function sourceConfig(investment) {
  const repo = investment === 'SOXL' ? process.env.LST_PATH ?? resolve(root, '../lst') : process.env.KST_PATH ?? resolve(root, '../kst');
  const local = selectedValues([`${repo}/.env`, `${repo}/apps/runner/.env`, `${repo}/.codex/config.local.toml`]);
  return {
    token: process.env[`${investment}_SLACK_TOKEN`] ?? local.SLACK_BOT_TOKEN,
    channel: process.env[`${investment}_SLACK_CHANNEL`] ?? local.SLACK_CHANNEL_ID
  };
}

export function readerToken() {
  if (process.env.MY_STOCK_READER_TOKEN) return process.env.MY_STOCK_READER_TOKEN;
  const path = resolve(dataDir, 'reader-token');
  if (!existsSync(path)) writeFileSync(path, randomBytes(32).toString('hex'), { mode: 0o600 });
  return readFileSync(path, 'utf8').trim();
}
