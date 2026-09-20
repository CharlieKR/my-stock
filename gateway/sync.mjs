import { readFile, writeFile, rename, open, unlink, stat } from 'node:fs/promises';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { dataDir, sourceConfig } from './config.mjs';
import { normalizeMessages, parseReport } from './parser.mjs';

export const cachePath = resolve(dataDir, 'reports.json');
export async function readCache() {
  try { return JSON.parse(await readFile(cachePath, 'utf8')); }
  catch (e) { if (e.code !== 'ENOENT') throw e; return { schemaVersion: 1, generatedAt: null, reports: [], fxRates: [], sources: [] }; }
}

export async function slackRead(method, config, params = {}) {
  if (!['conversations.history', 'conversations.replies'].includes(method)) throw new Error('Read-only method required');
  const url = new URL(`https://slack.com/api/${method}`);
  url.search = new URLSearchParams({ channel: config.channel, limit: '100', ...params }).toString();
  const response = await fetch(url, { headers: { Authorization: `Bearer ${config.token}` }, signal: AbortSignal.timeout(20000) });
  if (response.status === 429) throw new Error(`Slack 요청 제한 · ${response.headers.get('retry-after') ?? '60'}초 후 다시 시도`);
  if (!response.ok) throw new Error(`Slack HTTP ${response.status}`);
  const result = await response.json();
  if (!result.ok) throw new Error(`Slack ${result.error ?? 'unknown_error'}`);
  return result;
}

async function history(config, oldest) {
  const messages = [];
  const seen = new Set();
  let cursor = '';
  while (true) {
    const result = await slackRead('conversations.history', config, { oldest: String(oldest), ...(cursor ? { cursor } : {}) });
    messages.push(...result.messages ?? []);
    cursor = result.response_metadata?.next_cursor ?? '';
    if (!cursor) return { messages, complete: !result.has_more };
    if (seen.has(cursor)) return { messages, complete: false };
    seen.add(cursor);
  }
}

export async function syncReports(options = {}) {
  // The CLI and the HTTP server share one writer. A live app may refresh while
  // a full history backfill runs; serve the previous complete cache in that case.
  const lockPath = resolve(dataDir, 'sync.lock');
  let lock;
  try { lock = await open(lockPath, 'wx', 0o600); }
  catch (error) {
    if (error.code !== 'EEXIST') throw error;
    const info = await stat(lockPath).catch(() => null);
    if (!info) return readCache();
    const pid = Number(await readFile(lockPath, 'utf8').catch(() => ''));
    let alive = true;
    if (pid > 0) {
      try { process.kill(pid, 0); } catch (e) { alive = e.code !== 'ESRCH'; }
    }
    if (alive && Date.now() - info.mtimeMs < 15 * 60 * 1000) return readCache();
    await unlink(lockPath).catch(() => {});
    return syncReports(options);
  }
  try {
    await lock.writeFile(String(process.pid));
    return await collectReports(options);
  } finally {
    await lock.close();
    await unlink(lockPath).catch(() => {});
  }
}

async function collectReports({ full = false } = {}) {
  const cache = await readCache();
  const sources = [];
  // Re-normalize cached text when the parser improves; no historical writes.
  let reports = cache.reports.map(r => {
    const channel = r.slackURL?.match(/archives\/([^/]+)\//)?.[1];
    const parsed = channel && parseReport({ text: r.rawText, ts: r.threadTS }, r.investment, channel);
    return parsed ? { ...parsed, updatedAt: r.updatedAt } : r;
  });
  for (const investment of ['SOXL', 'HYXL']) {
    const config = sourceConfig(investment);
    if (!config.token || !config.channel) {
      sources.push({ investment, status: 'error', message: 'Slack 읽기 연결 정보가 없습니다.', lastSyncedAt: null });
      continue;
    }
    const priorSource = cache.sources.find(s => s.investment === investment);
    const prior = reports.filter(r => r.investment === investment);
    // Overlap seven days so post-settlement/RP edits are picked up.
    const priorSync = Date.parse(priorSource?.lastSyncedAt ?? '');
    const oldest = !full && priorSource?.historyVersion === 3 && priorSource?.historyComplete && prior.length && Number.isFinite(priorSync)
      ? priorSync / 1000 - 7 * 86400 : 0;
    try {
      const result = await history(config, oldest);
      const fresh = normalizeMessages(result.messages, investment, config.channel);
      for (let index = 0; index < fresh.length; index++) {
        const report = fresh[index];
        if (investment !== 'SOXL' || report.status !== 'pending') continue;
        let cursor = '';
        const replies = [];
        const seen = new Set();
        do {
          const thread = await slackRead('conversations.replies', config, { ts: report.threadTS, ...(cursor ? { cursor } : {}) });
          replies.push(...(thread.messages ?? []).filter(m => m.ts !== report.threadTS && /일일 리포트/.test(m.text ?? '')));
          cursor = thread.response_metadata?.next_cursor ?? '';
          if (cursor && seen.has(cursor)) throw new Error('과거 정산 스레드 페이지를 모두 읽지 못했습니다.');
          seen.add(cursor);
        } while (cursor);
        for (const reply of replies.sort((a,b) => Number(a.ts) - Number(b.ts))) {
          const parsed = parseReport({ text: `${report.rawText}\n${reply.text}`, ts: report.threadTS, edited: { ts: reply.edited?.ts ?? reply.ts } }, investment, config.channel);
          if (parsed?.status === 'settled') fresh[index] = parsed;
        }
      }
      const merged = new Map(prior.map(r => [r.id, r]));
      for (const r of fresh) {
        if (merged.get(r.id)?.status === 'settled' && r.status !== 'settled') continue;
        merged.set(r.id, r);
      }
      reports = [...reports.filter(r => r.investment !== investment), ...merged.values()];
      sources.push({ investment, status: result.complete ? 'ready' : 'partial', message: result.complete ? 'Slack 전체 리포트 연결됨' : '일부 과거 메시지가 아직 수집되지 않았습니다.', lastSyncedAt: new Date().toISOString(), historyComplete: result.complete, historyVersion: 3 });
    } catch (e) {
      sources.push({ investment, status: 'error', message: e.message, lastSyncedAt: priorSource?.lastSyncedAt ?? null, historyComplete: priorSource?.historyComplete ?? false });
    }
  }
  reports.sort((a,b) => a.date.localeCompare(b.date) || a.investment.localeCompare(b.investment));
  let fxRates = cache.fxRates ?? [];
  let fxMessage = null;
  const dates = reports.filter(r => r.status === 'settled').map(r => r.date);
  if (dates.length) {
    try {
      const from = new Date(`${dates[0]}T00:00:00Z`); from.setUTCDate(from.getUTCDate() - 7);
      const url = new URL('https://api.frankfurter.dev/v2/rates');
      url.search = new URLSearchParams({ base: 'USD', quotes: 'KRW', from: from.toISOString().slice(0,10), to: dates.at(-1) }).toString();
      const response = await fetch(url, { signal: AbortSignal.timeout(20000) });
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      const rows = await response.json();
      if (!Array.isArray(rows) || !rows.length) throw new Error('empty rates');
      const valid = rows.filter(r => r.quote === 'KRW' && Number.isFinite(r.rate) && r.rate > 0).map(r => ({ date: r.date, usdKrw: r.rate }));
      if (!valid.length) throw new Error('missing KRW rates');
      fxRates = [...new Map([...fxRates, ...valid].map(r => [r.date, r])).values()].sort((a,b) => a.date.localeCompare(b.date));
    } catch { fxMessage = '환율을 갱신하지 못했습니다. 저장된 날짜별 환율만 사용합니다.'; }
  }
  const result = { schemaVersion: 1, generatedAt: new Date().toISOString(), reports, fxRates, fxSource: 'Frankfurter · reference rate', fxMessage, sources };
  await writeFile(`${cachePath}.tmp`, JSON.stringify(result), { mode: 0o600 });
  await rename(`${cachePath}.tmp`, cachePath);
  return result;
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  const result = await syncReports({ full: process.argv.includes('--full') });
  console.log(JSON.stringify({ reportCount: result.reports.length, sources: result.sources, fxRateCount: result.fxRates.length, fxMessage: result.fxMessage }, null, 2));
  if (result.sources.some(s => s.status === 'error')) process.exitCode = 1;
}
