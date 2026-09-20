// Adapters for lst buildMainSettlementSummary and kst formatDailySummaryText.
// No trading modules are imported or executed.
export function amount(text) {
  const match = String(text ?? '').replaceAll(',', '').match(/[+−-]?\s*[$₩]?\s*([+−-]?\d+(?:\.\d+)?)/);
  if (!match) return null;
  const value = Number(match[0].replace(/[$₩\s]/g, '').replaceAll('−', '-'));
  return Number.isFinite(value) ? value : null;
}

export function parseReport(message, investment, channel) {
  const raw = message.text ?? '';
  const titles = investment === 'SOXL'
    ? ['SOXL 매매', 'SOXL 동파/Tide', 'LS 자동매매', '동파/떨사']
    : ['HYXL 매매', 'HYXL 동파/Tide'];
  const heading = raw.split('\n')[0].replaceAll('*', '').replace(/:[a-z_0-9+-]+:/g, '').trim();
  if (!titles.some(title => heading.startsWith(`${title} (`))) return null;
  const date = raw.match(/\((\d{4}-\d{2}-\d{2})\)/)?.[1];
  if (!date) return null;
  const clean = raw.replaceAll('```', '').replaceAll('*', '').replace(/:[a-z_0-9+-]+:/g, '');
  const lines = clean.split('\n').map(s => s.trim()).filter(Boolean);
  const line = prefix => lines.find(s => new RegExp(`^${prefix}\\s*:`).test(s));
  const assets = line('자산');
  const cumulative = line('누적');
  // Earlier SOXL reports publish settlement only inside the daily thread.
  // Read the explicit combined section, never an individual strategy balance.
  const legacy = investment === 'SOXL'
    ? clean.match(/(?:^|\n)\s*종합(?:\s*\([^\n)]*\))?\s*\n([\s\S]*?)(?:\n\s*\n|$)/)?.[0] : null;
  const totalAssets = amount(assets?.match(/총\s+([^/]+)/)?.[1])
    ?? amount(legacy?.match(/(?:총\s*자산|장부 자산)\s*:\s*([^\n(]+)/)?.[1]);
  const stockValue = amount(assets?.match(/주식\s+(.+)/)?.[1])
    ?? amount(legacy?.match(/주식(?:평가)?\s*:?\s*(\$[\d,.]+)/)?.[1]);
  const legacyPnl = legacy?.match(/(?:누적|수익률)\s*:?\s*([+−-]?[\d,.]+)%\s*\(([+−$\d,.-]+)\)/);
  const principal = amount(legacy?.match(/원금\s+(\$[\d,.]+)/)?.[1]);
  const cumulativePnl = amount(cumulative?.split(':').slice(1).join(':'))
    ?? amount(legacyPnl?.[2])
    ?? (legacy && totalAssets != null && principal != null ? totalAssets - principal : null);
  const cumulativeReturn = amount(cumulative?.match(/\(([^%]+)%\)/)?.[1])
    ?? amount(legacy?.match(/(?:누적|수익률)\s*:?\s*([+−-]?[\d,.]+)%/)?.[1]);
  const status = /휴장/.test(raw) ? 'closed' : (/정산 완료|정산 요약/.test(raw) || legacy) && totalAssets != null ? 'settled' : 'pending';
  const ignored = /^(📅|✅|📊|⚠|자산\s*:|누적\s*:|현금\s*:|비중\s*:|정산 완료|정산 요약|리밸런싱 요약)/;
  const details = lines.filter(s => !ignored.test(s) && !titles.some(title => s.includes(title)));
  return {
    id: `${investment}-${date}`, investment, date,
    currency: investment === 'SOXL' ? 'USD' : 'KRW',
    status, totalAssets, stockValue,
    cash: totalAssets != null && stockValue != null ? totalAssets - stockValue : null,
    cumulativePnl, cumulativeReturn,
    dailyPnl: amount(line('오늘')?.split(':').slice(1).join(':')),
    dailyPnlLabel: '오늘 손익',
    details: details.map((text, i) => ({ id: `${investment}-${date}-${i}`, title: text.split(':')[0].trim(), text: text.includes(':') ? text.slice(text.indexOf(':') + 1).trim() : text })),
    rawText: raw, slackURL: `https://slack.com/archives/${channel}/p${String(message.ts).replace('.', '')}`,
    threadTS: message.ts,
    updatedAt: new Date(Number(message.edited?.ts ?? message.ts) * 1000).toISOString()
  };
}

export function normalizeMessages(messages, investment, channel) {
  const days = new Map();
  for (const msg of [...messages].sort((a,b) => Number(a.ts) - Number(b.ts))) {
    const report = parseReport(msg, investment, channel);
    if (!report) continue;
    const prior = days.get(report.date);
    if (prior?.status === 'settled' && report.status !== 'settled') continue;
    days.set(report.date, report);
  }
  return [...days.values()].sort((a,b) => a.date.localeCompare(b.date));
}
