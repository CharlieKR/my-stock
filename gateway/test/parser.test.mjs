import test from 'node:test';
import assert from 'node:assert/strict';
import { amount, parseReport, normalizeMessages } from '../parser.mjs';

const soxl = { ts: '1789714804.501599', text: ':date: *SOXL 매매* (2026-09-18)\n:white_check_mark: *정산 완료* (2026-09-18)\n```\n체결 : 없음\n자산 : 총 $1,250.50 / 주식 $250.50\n누적 : +$250.50 (+25.05%)\n오늘 : -$10.25 (-0.81%)\n현금 : $1,000.00\nRP : 누적 +$2.15 (+$0.03)\nTail : 오늘 미진입 / 누적 +$50.20\n```' };
test('SOXL dollars, losses, detail rows and source link', () => {
  const r = parseReport(soxl, 'SOXL', 'CEXAMPLE');
  assert.equal(r.totalAssets, 1250.5); assert.equal(r.cash, 1000);
  assert.equal(r.cumulativePnl, 250.5); assert.equal(r.cumulativeReturn, 25.05);
  assert.equal(r.dailyPnl, -10.25); assert.equal(r.status, 'settled');
  assert.deepEqual(r.details.map(d => d.title), ['체결', '오늘', 'RP', 'Tail']);
  assert.match(r.slackURL, /p1789714804501599$/);
});
test('HYXL won and missing cumulative data remain distinct from zero', () => {
  const r = parseReport({ ts: soxl.ts, text: '*HYXL 매매* (2026-09-18)\n*정산 요약*\n자산 : 총 2,500,000원 / 주식 0원\nCMA : 누적 +25원' }, 'HYXL', 'CEXAMPLE');
  assert.equal(r.currency, 'KRW'); assert.equal(r.cash, 2500000);
  assert.equal(r.cumulativePnl, null); assert.equal(r.stockValue, 0);
});
test('rejects unrelated reports and keeps the market date', () => {
  assert.equal(parseReport(soxl, 'HYXL', 'CEXAMPLE'), null);
  assert.equal(parseReport({ ...soxl, text: '미장 ' + soxl.text.replace('SOXL 매매', '미장 매매') }, 'SOXL', 'CEXAMPLE'), null);
  assert.equal(parseReport(soxl, 'SOXL', 'CEXAMPLE').date, '2026-09-18');
});
test('pending and holiday messages do not fabricate assets', () => {
  const pending = parseReport({ ...soxl, text: '*SOXL 매매* (2026-09-21)' }, 'SOXL', 'CEXAMPLE');
  assert.equal(pending.totalAssets, null); assert.equal(pending.status, 'pending');
  const closed = parseReport({ ...soxl, text: '*SOXL 매매* (2026-09-07)\n미국 장 휴장' }, 'SOXL', 'CEXAMPLE');
  assert.equal(closed.status, 'closed');
});
test('newer planning message cannot overwrite a settled report', () => {
  const reports = normalizeMessages([soxl, { ts: '1789715804.501599', text: '*SOXL 매매* (2026-09-18)' }], 'SOXL', 'CEXAMPLE');
  assert.equal(reports.length, 1); assert.equal(reports[0].totalAssets, 1250.5);
});
test('negative currency notation and absent numbers', () => {
  assert.equal(amount('−₩1,234'), -1234); assert.equal(amount('$-1.25'), -1.25);
  assert.equal(amount('없음'), null); assert.equal(amount(undefined), null);
});
test('historical SOXL dongpa/Tide header maps to the same investment', () => {
  const historical = { ...soxl, text: soxl.text.replace('SOXL 매매', 'SOXL 동파/Tide').replace('정산 완료', '정산 요약') };
  const report = parseReport(historical, 'SOXL', 'CEXAMPLE');
  assert.equal(report.totalAssets, 1250.5);
  assert.equal(report.investment, 'SOXL');
  assert.ok(report.details.every(d => !d.title.includes('SOXL 동파/Tide')));
});
test('previous daily titles are included without mixing other portfolios or test posts', () => {
  for (const title of ['LS 자동매매', '동파/떨사']) {
    assert.equal(parseReport({ ...soxl, text: soxl.text.replace('SOXL 매매', title) }, 'SOXL', 'CEXAMPLE').totalAssets, 1250.5);
  }
  for (const title of ['키움/LS', '미장 LIVE 요약', 'TEST SOXL 매매']) {
    assert.equal(parseReport({ ...soxl, text: soxl.text.replace('SOXL 매매', title) }, 'SOXL', 'CEXAMPLE'), null);
  }
  assert.equal(parseReport({ ...soxl, text: '*HYXL 동파/Tide* (2026-06-29)' }, 'HYXL', 'CEXAMPLE').status, 'pending');
});
test('historical thread reads combined assets and profit rather than strategy totals', () => {
  const text = '*LS 자동매매* (2026-04-01)\n*일일 리포트*\n동파\n총 자산: $900\n\n:zap: *종합* (원금 $1,000)\n주식평가: $400\n총 자산: $1,250\n수익률: +25.00% (+$250)\n\n다른 내용';
  const r = parseReport({ ...soxl, text }, 'SOXL', 'CEXAMPLE');
  assert.equal(r.status, 'settled'); assert.equal(r.date, '2026-04-01');
  assert.equal(r.totalAssets, 1250); assert.equal(r.stockValue, 400);
  assert.equal(r.cumulativePnl, 250); assert.equal(r.cumulativeReturn, 25);
  assert.equal(parseReport({ ...soxl, text: text.split(':zap:')[0] }, 'SOXL', 'CEXAMPLE').status, 'pending');
});
test('historical book assets derive PnL only from explicit principal', () => {
  const text = '*LS 자동매매* (2026-03-31)\n*일일 리포트*\n*종합*\n주식평가: $400\n장부 자산: $1,200 (원금 $1,000)\n총 수익률: +20.00%';
  const r = parseReport({ ...soxl, text }, 'SOXL', 'CEXAMPLE');
  assert.equal(r.totalAssets, 1200); assert.equal(r.cumulativePnl, 200);
  const missing = parseReport({ ...soxl, text: text.replace(' (원금 $1,000)', '') }, 'SOXL', 'CEXAMPLE');
  assert.equal(missing.cumulativePnl, null);
});
