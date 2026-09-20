import {readFile, writeFile, rename} from 'node:fs/promises';
import {join} from 'node:path';
import {dataDir, sourceConfig} from './config.mjs';
import {slackRead} from './sync.mjs';
import {normalizeOrderThread} from './order-history.mjs';

const archivePath = join(dataDir, 'legacy-reports.json');
const args = Object.fromEntries(process.argv.slice(2).map(value => value.split('=')));
const archive = JSON.parse(await readFile(archivePath, 'utf8'));
const latest = archive.reports.map(report => report.date).sort().at(-1);
const end = args['--to'] ?? latest;
const startDate = new Date(`${end}T00:00:00Z`);
startDate.setUTCDate(startDate.getUTCDate() - 31);
const start = args['--from'] ?? startDate.toISOString().slice(0, 10);
const selected = archive.reports.filter(report =>
  report.threadTS && report.date >= start && report.date <= end
    && ['SOXL', 'HYXL'].includes(report.investment));

async function save() {
  const temporary = `${archivePath}.orders.tmp`;
  await writeFile(temporary, JSON.stringify(archive), {mode: 0o600});
  await rename(temporary, archivePath);
}

let imported = 0;
for (const report of selected) {
  const config = sourceConfig(report.investment);
  if (!config.token || !config.channel) throw new Error(`${report.investment} Slack 읽기 설정이 없습니다.`);
  const thread = await slackRead('conversations.replies', config, {ts: report.threadTS});
  const messages = normalizeOrderThread(thread.messages ?? []);
  if (messages.length) {
    report.messages = messages;
    imported += 1;
    await save();
  }
  console.log(`${report.id} · ${messages.length}단계`);
}
console.log(`${start} ~ ${end} · ${imported}/${selected.length}일 주문 이력 저장`);
