import Decimal from 'decimal.js';

const clean = value => String(value ?? '')
  .replace(/:[a-z_0-9+-]+:/gi, '')
  .replaceAll('*', '')
  .replaceAll('&lt;', '<')
  .replaceAll('&gt;', '>')
  .trim();

const symbolName = value => (value || 'SOXL').replace(/\([^)]*\)$/u, '');
const quantity = value => Number(String(value).replaceAll(',', ''));
const instant = ts => new Date(Number(ts) * 1000).toISOString();
const money = (value, mark) => {
  const fixed = new Decimal(value).toFixed(mark === '$' ? 2 : 0);
  const [whole, fraction] = fixed.split('.');
  const grouped = Number(whole).toLocaleString('en-US');
  return mark + grouped + (fraction ? `.${fraction}` : '');
};

function parsePlan(text) {
  const orders = [];
  for (const line of clean(text).split('\n')) {
    const match = line.match(
      /^-\s*(매수|매도)\s+(?:(\S+)\s+)?([\d,]+)주\s*@\s*([$₩])([\d,.]+)\s*\/\s*(?:총\s*)?([$₩])([\d,.]+)(?:\s+(\S+))?/u);
    if (!match) continue;
    orders.push({
      side: match[1], symbol: symbolName(match[2]), qty: quantity(match[3]),
      price: money(match[5].replaceAll(',', ''), match[4]),
      amount: money(match[7].replaceAll(',', ''), match[6]), type: match[8] ?? '',
    });
  }
  return orders;
}

function orderLine(order, status) {
  const note = [order.type, status].filter(Boolean).join(' · ');
  return `- ${order.side} ${order.symbol} ${order.qty.toLocaleString('en-US')}주 @ ${order.price} / ${order.amount}${note ? ` ${note}` : ''}`;
}

function executionStatus(text) {
  const status = clean(text).match(/^상태\s*:\s*(.+)$/mu)?.[1]
    ?.replace(/\s*\/\s*LIVE.*$/u, '')
    .replaceAll(' / ', ' · ');
  return status || '제출 완료';
}

function parseResult(text, plan) {
  const orders = [];
  const consumed = new Set();
  let section = '';
  for (const source of clean(text).split('\n')) {
    const line = source.trim();
    if (/^체결\s*$/u.test(line)) { section = 'filled'; continue; }
    if (/^미체결(?:\/거부)?\s*$/u.test(line)) { section = 'unfilled'; continue; }
    if (!line.startsWith('-') || !section || /^-\s*없음\s*$/u.test(line)) continue;
    const match = line.match(
      /^-\s*(?:(동파|동파법|Tide|Tail|키움|LS)\s+)?(매수|매도)\s+(?:(\S+)\s+)?([\d,]+)주(?:\s*@\s*([$₩])([\d,.]+))?(?:\s*\/\s*(?:총\s*)?([$₩])([\d,.]+))?(?::\s*(.+))?$/u);
    if (!match) continue;
    const side = match[2];
    const symbol = symbolName(match[3]);
    const qty = quantity(match[4]);
    const planIndex = plan.findIndex((candidate, index) =>
      !consumed.has(index) && candidate.side === side && candidate.qty === qty
        && (candidate.symbol === symbol || symbol === 'SOXL'));
    const fallbackIndex = planIndex >= 0 ? planIndex : plan.findIndex((candidate, index) =>
      !consumed.has(index) && candidate.side === side && candidate.qty === qty);
    const planned = fallbackIndex >= 0 ? plan[fallbackIndex] : undefined;
    if (fallbackIndex >= 0) consumed.add(fallbackIndex);
    const price = match[5]
      ? money(match[6].replaceAll(',', ''), match[5])
      : planned?.price;
    if (!price) continue;
    const amount = match[7]
      ? money(match[8].replaceAll(',', ''), match[7])
      : money(
        new Decimal(price.slice(1).replaceAll(',', '')).times(qty), price.startsWith('$') ? '$' : '₩');
    const reason = match[9] ?? '';
    const status = section === 'filled'
      ? '체결 완료'
      : /초과|필요|거부|실패/u.test(reason) ? '거부' : '미체결';
    orders.push({side, symbol, qty, price, amount, type: planned?.type ?? '', status});
  }
  return orders;
}

export function normalizeOrderThread(messages) {
  const planCandidates = messages
    .filter(message => /주문표|내일 주문표 발송/u.test(clean(message.text)))
    .map(message => ({message, orders: parsePlan(message.text)}))
    .filter(candidate => candidate.orders.length);
  const selectedPlan = planCandidates.at(-1);
  const execution = messages.filter(message => /주문\s*실행/u.test(clean(message.text))).at(-1);
  const result = messages.filter(message => /주문\s*결과/u.test(clean(message.text))).at(-1);
  const output = [];
  if (selectedPlan) {
    output.push({
      id: `${selectedPlan.message.ts}-plan`, date: instant(selectedPlan.message.ts),
      text: `주문표 생성\n${selectedPlan.orders.map(order => orderLine(order, '예정')).join('\n')}`,
    });
  }
  if (execution) {
    output.push({
      id: `${execution.ts}-execution`, date: instant(execution.ts),
      text: `주문 제출\n${executionStatus(execution.text)}`,
    });
  }
  if (result) {
    const rows = parseResult(result.text, selectedPlan?.orders ?? []);
    output.push({
      id: `${result.ts}-result`, date: instant(result.ts),
      text: rows.length
        ? `체결 결과\n${rows.map(order => orderLine(order, order.status)).join('\n')}`
        : `체결 결과\n${/체결\s*\n-\s*없음/u.test(clean(result.text)) ? '체결 없음' : '결과 확인'}`,
    });
  }
  return output.sort((a, b) => a.date.localeCompare(b.date));
}
