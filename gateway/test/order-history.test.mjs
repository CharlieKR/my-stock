import test from 'node:test';
import assert from 'node:assert/strict';
import {normalizeOrderThread} from '../order-history.mjs';

test('normalizes a Slack order thread without strategy labels or report prose', () => {
  const messages = [
    {ts:'1',text:'주문표\n동파\n- 매도 15주 @ $166.26 / $2,493.90 LOC\nTide\n- 매수 46주 @ $143.85 / $6,617.10 LOC'},
    {ts:'2',text:'주문실행\n동파\n- 매도 15주 LOC 접수\nTide\n- 매수 46주 LIMIT 체결'},
    {ts:'3',text:'주문결과\n체결\n- Tide 매수 SOXL 46주 @ $126.65\n미체결\n- 동파 매도 SOXL 15주'},
    {ts:'4',text:'전략비교\n결론: 동일'},
  ];
  const result=normalizeOrderThread(messages);
  assert.deepEqual(result.map(message=>message.text.split('\n')[0]),['주문표 생성','주문 제출','체결 결과']);
  assert.doesNotMatch(result.map(message=>message.text).join('\n'),/동파|Tide|전략비교/);
  assert.match(result[2].text,/매수 SOXL 46주.*\$126.65.*\$5,825.90.*체결 완료/);
  assert.match(result[2].text,/매도 SOXL 15주.*\$166.26.*미체결/);
});

test('keeps rejection status for Korean orders and strips broker instrument codes', () => {
  const messages = [
    {ts:'1',text:'내일 주문표 발송\n- 매도 ACE(0194T0) 271주 @ ₩29,300 / ₩7,940,300\n- 매수 KODEX(0193T0) 1,876주 @ ₩9,410 / ₩17,653,160'},
    {ts:'2',text:'주문 실행\n상태 : 제출 1건 / 거부 1건 / LIVE'},
    {ts:'3',text:'주문결과\n체결\n- 없음\n미체결/거부\n- 동파 매도 ACE(0194T0) 271주 @ ₩29,300: 주문단가가 상한가를 초과합니다.\n- Tide 매수 KODEX(0193T0) 1,876주 @ ₩9,410: 미체결 대기'},
  ];
  const result=normalizeOrderThread(messages);
  assert.match(result[0].text,/매도 ACE 271주/);
  assert.match(result[1].text,/제출 1건 · 거부 1건/);
  assert.match(result[2].text,/매도 ACE 271주.*거부/);
  assert.match(result[2].text,/매수 KODEX 1,876주.*미체결/);
});
