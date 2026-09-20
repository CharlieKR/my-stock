import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { PGlite } from '@electric-sql/pglite';
import { calculatePerformance, performanceWithPeriods, periodStart } from '../performance.mjs';
import { normalizeBatches, mergeDailyReport } from '../reports-v2.mjs';

const report=(date,nav,extra={})=>({id:'SOXL-'+date,investment:'SOXL',date,currency:'USD',status:'settled',totalAssets:String(nav),quality:'broker_reconciled',cashEvents:[],cashflowCoverageFrom:'2026-01-01',...extra});
const when=new Date('2026-04-01T12:00:00Z');
test('rolling presets clamp months and include seven calendar days',()=>{
  assert.equal(periodStart('2026-09-18','week'),'2026-09-12');
  assert.equal(periodStart('2026-03-31','month'),'2026-03-01');
  assert.equal(periodStart('2024-02-29','year'),'2023-03-01');
  assert.equal(periodStart('2026-09-18','quarter'),'2026-06-19');
  assert.equal(periodStart('2026-09-18','all'),null);
});
test('one-week performance excludes earlier month profit and deposits while preserving opening NAV',()=>{
  const rows=Array.from({length:32},(_,day)=>report(day===0?'2026-02-28':`2026-03-${String(day).padStart(2,'0')}`,100+day*10));
  rows.at(-1).cashEvents=[{id:'old',date:'2026-03-02',kind:'deposit',amount:'20',currency:'USD'},
    {id:'inside',date:'2026-03-28',kind:'deposit',amount:'10',currency:'USD'}];
  const result=performanceWithPeriods(rows,[],'SOXL',when);
  const week=result.periods.week;
  assert.equal(week.points.length,7);assert.equal(week.points[0].date,'2026-03-25');
  assert.equal(week.summary.startDate,'2026-03-24');assert.equal(week.summary.profit,'60.00000000');
  assert.equal(week.months[0].profit,'60.00000000');assert.equal(week.months[0].partial,true);
  assert.equal(result.summary.profit,'280.00000000'); // first observed NAV is a partial-period baseline
  assert.equal(result.summary.partial,true);
});
test('cash deposits do not become profit; decimal cents and Dietz weighting',()=>{
  const events=[{id:'a',date:'2026-03-15',kind:'deposit',amount:'100',currency:'USD'}];
  const result=calculatePerformance([report('2026-02-27',100),report('2026-03-15',200),report('2026-03-31','210.01',{cashEvents:events})],[],'SOXL',when);
  const march=result.months[0];
  assert.equal(march.profit,'10.01000000');assert.equal(march.cashflow,'100.00000000');assert.equal(march.estimated,true);
  assert.ok(Number(march.returnPercent)>6&&Number(march.returnPercent)<7);
});
test('archive, missing ledger and initial month do not invent returns',()=>{
  const r=calculatePerformance([report('2026-03-01',100,{cashflowCoverageFrom:null}),report('2026-03-31',120,{cashflowCoverageFrom:null})],[],'SOXL',when);
  assert.equal(r.months[0].profit,null);assert.equal(r.months[0].returnPercent,null);assert.equal(r.months[0].endAssets,'120.00000000');
});
const archived=(date,nav,pnl,extra={})=>report(date,nav,{quality:'legacy_archive',cashflowCoverageFrom:null,cumulativePnl:pnl,...extra});
test('daily P&L bridges missing cumulative history and removes deposits from return',()=>{
  const rows=[archived('2026-06-29',100,null),archived('2026-06-30',151,null,{dailyPnl:1})];
  const result=calculatePerformance(rows,[],'SOXL',new Date('2026-09-20')).months[0];
  assert.equal(result.profit,'1.00000000');assert.equal(result.cashflow,'50.00000000');
  assert.equal(result.returnPercent,'1.00000000');assert.equal(result.coverageLabel,'6.29부터');
  assert.match(result.reason,/일별 손익/);
  const gap=calculatePerformance([rows[0],{...rows[1],date:'2026-07-02'}],[],'SOXL',new Date('2026-09-20'));
  assert.equal(gap.summary.profit,null);assert.equal(gap.summary.coverageLabel,'근거 부족');
});
test('combined June includes a new investment without counting its opening balance as profit',()=>{
  const rows=[archived('2026-05-29',100,0),archived('2026-06-29',110,10),archived('2026-06-30',120,20),
    archived('2026-06-29',1000,null,{id:'HYXL-a',investment:'HYXL',currency:'KRW'}),
    archived('2026-06-30',990,null,{id:'HYXL-b',investment:'HYXL',currency:'KRW',dailyPnl:-10})];
  const rates=rows.map(r=>({date:r.date,usdKrw:1000}));
  const p=calculatePerformance(rows,rates,'all',new Date('2026-09-20')).months[0];
  assert.equal(p.month,'2026-06');assert.equal(p.profit,'19990.00000000');
  assert.equal(p.cashflow,'1000.00000000');assert.equal(p.partial,false);
  assert.equal(p.startDate,'2026-05-29');assert.equal(p.estimated,true);
});
test('carried daily P&L is counted once and ongoing months name their last date',()=>{
  const rows=[archived('2026-08-31',100,null),archived('2026-09-01',110,null,{dailyPnl:10}),
    archived('2026-08-31',1000,0,{id:'HYXL-a',investment:'HYXL',currency:'KRW'}),
    archived('2026-09-02',1020,20,{id:'HYXL-b',investment:'HYXL',currency:'KRW'})];
  const p=calculatePerformance(rows,rows.map(r=>({date:r.date,usdKrw:1000})),'all',new Date('2026-09-20')).months[0];
  assert.equal(p.profit,'10020.00000000');assert.equal(p.coverageLabel,'9.2까지');
});
test('historical cumulative P&L restores partial first month and excludes capital additions',()=>{
  const rows=[archived('2026-03-25',100,0),archived('2026-03-26',210,10),archived('2026-03-31',220,20)];
  const p=calculatePerformance(rows,[],'SOXL',when);
  assert.equal(p.months[0].profit,'20.00000000');
  assert.equal(p.months[0].cashflow,'100.00000000');
  assert.equal(p.months[0].estimated,true);
  assert.equal(p.months[0].partial,true);
  assert.equal(p.months[0].method,'inferred_capital_dietz');
  assert.equal(p.summary.profit,'20.00000000');
  assert.ok(Number(p.summary.returnPercent)>10&&Number(p.summary.returnPercent)<11);
});
test('combined history starts with first investment and excludes a later account entry',()=>{
  const rows=[archived('2026-03-25',100,0),archived('2026-03-26',110,10),archived('2026-03-31',120,20),
    archived('2026-03-26',500,50,{id:'HYXL-a',investment:'HYXL',currency:'KRW'}),
    archived('2026-03-31',550,100,{id:'HYXL-b',investment:'HYXL',currency:'KRW'})];
  const fx=[{date:'2026-03-25',usdKrw:1000},{date:'2026-03-26',usdKrw:1000},{date:'2026-03-31',usdKrw:1100}];
  const p=calculatePerformance(rows,fx,'all',when);
  assert.equal(p.points[0].date,'2026-03-25');
  assert.deepEqual(p.points[0].includedInvestments,['SOXL']);
  assert.equal(p.summary.profit,'32050.00000000'); // 20 USD gain, FX change and 50 KRW gain
  assert.equal(p.summary.cashflow,'500.00000000'); // first observed HYXL NAV is not profit
});
test('missing initial cumulative P&L visibly shortens the profit calculation interval',()=>{
  const p=calculatePerformance([archived('2026-03-01',100,null),archived('2026-03-02',90,10),archived('2026-03-31',120,20)],[],'SOXL',when);
  assert.equal(p.points[0].date,'2026-03-01');
  assert.equal(p.summary.startDate,'2026-03-02');
  assert.equal(p.summary.profit,'10.00000000');
  assert.equal(p.summary.partial,true);
  assert.match(p.summary.reason,/2026-03-02/);
  const missing=calculatePerformance([archived('2026-03-01',100,null),archived('2026-03-31',120,null)],[],'SOXL',when);
  assert.equal(missing.summary.profit,null);
  assert.equal(missing.summary.estimated,false);
});
test('an investment with established history cannot silently disappear when stale',()=>{
  const p=calculatePerformance([archived('2026-03-01',100,0),archived('2026-03-31',120,20),
    archived('2026-03-01',500,0,{id:'HYXL-a',investment:'HYXL',currency:'KRW'})],
    [{date:'2026-03-01',usdKrw:1000},{date:'2026-03-31',usdKrw:1000}],'all',when);
  assert.deepEqual(p.points.map(p=>p.date),['2026-03-01']);
});
test('combined return includes FX and excludes external USD deposit at event rate',()=>{
  const events=[{id:'a',date:'2026-03-15',kind:'deposit',amount:'100',currency:'USD'}];
  const rows=[report('2026-02-27',100),report('2026-03-31',200,{cashEvents:events}),
    report('2026-02-27',100000,{id:'HYXL-a',investment:'HYXL',currency:'KRW'}),report('2026-03-31',100000,{id:'HYXL-b',investment:'HYXL',currency:'KRW'})];
  const fx=[{date:'2026-02-27',usdKrw:'1000'},{date:'2026-03-15',usdKrw:'1100'},{date:'2026-03-31',usdKrw:'1200'}];
  assert.equal(calculatePerformance(rows,fx,'all',when).months[0].profit,'30000.00000000');
});
test('future or incomplete source is not a combined valuation',()=>{
  const rows=[report('2026-03-31',100,{availableDate:'2026-04-01'}),report('2026-03-31',100,{investment:'HYXL',currency:'KRW'})];
  assert.equal(calculatePerformance(rows,[{date:'2026-03-31',usdKrw:1000}],'all',new Date('2026-03-31T12:00:00Z')).points.length,0);
});
const batch=(extra={})=>({schemaVersion:2,investment:'HYXL',portfolioId:'kiwoom_main',date:'2026-09-18',stage:'settled',capturedAt:'2026-09-18T08:00:00Z',currency:'KRW',nav:'100',stockValue:'80',cash:'20',principal:'90',cumulativePnl:'10',dailyPnl:'1',quality:'broker_reconciled',cashEvents:[],details:[],...extra});
test('missing one HYXL account cannot silently shrink total assets',()=>{
  assert.equal(normalizeBatches([batch()],'HYXL')[0].totalAssets,null);
  const complete=normalizeBatches([batch(),batch({portfolioId:'ls_main',nav:'200'})],'HYXL')[0];
  assert.equal(complete.totalAssets,'300');assert.deepEqual(complete.details.map(d=>[d.title,d.text]),[['체결','없음']]);
});
test('future plan is queryable without becoming a valuation',()=>{
  const plan=batch({date:'2026-09-21',stage:'plan',nav:null,stockValue:null,cash:null,principal:null,
    cumulativePnl:null,dailyPnl:null,quality:'incomplete',orders:[{symbol:'0193T0.KS',side:'BUY',qty:2141,limit_price:12660,status:'ready'}]});
  const result=normalizeBatches([plan],'HYXL')[0];
  assert.equal(result.status,'pending');assert.equal(result.totalAssets,null);
  assert.equal(result.hasOrderPlan,true);assert.equal(result.plannedOrderCount,1);
  assert.deepEqual(result.details,[]);
  assert.match(result.messages.at(-1).text,/주문표 생성.*매수.*2,141주.*₩12,660.*₩27,105,060.*예정/s);
});
test('plan, submission and fills are presented once in chronological order without account names',()=>{
  const rows=[
    batch({date:'2026-09-21',stage:'plan',capturedAt:'2026-09-18T07:30:00Z',nav:null,quality:'incomplete',orders:[{id:'a',symbol:'KODEX',side:'BUY',qty:2,limit_price:100,status:'ready'}]}),
    batch({date:'2026-09-21',stage:'execution',capturedAt:'2026-09-21T00:01:00Z',nav:null,quality:'incomplete',orders:[{id:'a',symbol:'KODEX',side:'BUY',qty:2,limit_price:100,status:'SENT'}]}),
    batch({date:'2026-09-21',stage:'settled',capturedAt:'2026-09-21T07:00:00Z',orders:[{id:'a',symbol:'KODEX',side:'BUY',qty:2,limit_price:100,status:'FILLED',filled_qty:2}],evidence:{fills:[{order_id:'a',symbol:'KODEX',qty:2,price:99,filled_at:'2026-09-21T06:59:00Z'}]}}),
  ];
  const messages=normalizeBatches(rows,'HYXL')[0].messages;
  assert.deepEqual(messages.map(m=>m.text.split('\n')[0]),['주문표 생성','주문 제출','체결 결과']);
  assert.doesNotMatch(messages.map(m=>m.text).join('\n'),/kiwoom_main|동파|Tide/);
  assert.match(messages[1].text,/제출 완료/);assert.match(messages[2].text,/체결 완료/);
});
test('settled SENT orders are unfilled; partial fills show only the remaining quantity',()=>{
  const source=batch({orders:[{id:'a',symbol:'0193T0.KS',side:'BUY',qty:10,limit_price:100,status:'SENT',filled_qty:4}],
    evidence:{fills:[{order_id:'a',symbol:'0193T0.KS',qty:4,price:99}]}});
  const text=normalizeBatches([source],'HYXL')[0].messages[0].text;
  assert.match(text,/KODEX 4주 @ ₩99 \/ ₩396 체결 완료/);
  assert.match(text,/KODEX 6주 @ ₩100 \/ ₩600 미체결/);
  assert.doesNotMatch(text,/제출 완료/);
});
test('SOXL matched fill evidence avoids duplicating full fills as unfilled',()=>{
  const source=batch({investment:'SOXL',portfolioId:'soxl_live',currency:'USD',orders:[
    {id:'a',symbol:'SOXL',side:'sell',qty:10,order_price:100,status:'filled',trade_type:'main'}],
    evidence:{fills:[['a',{matchedQty:10,matchedAmount:1010}]]}});
  const text=normalizeBatches([source],'SOXL')[0].messages[0].text;
  assert.match(text,/10주 @ \$101 \/ \$1,010 체결 완료/);
  assert.doesNotMatch(text,/미체결|main/);
});
test('execution updates preserve historical settlement and its independent fill result',()=>{
  const prior={...archived('2026-09-18',100,10),messages:[
    {id:'p',text:'주문표 생성',date:'2026-09-18T01:00:00Z'},
    {id:'f',text:'체결 결과',date:'2026-09-18T07:00:00Z'}]};
  const current={...prior,status:'pending',totalAssets:null,messages:[
    {id:'s',text:'주문 제출',date:'2026-09-18T06:00:00Z'}]};
  const merged=mergeDailyReport(prior,current);
  assert.equal(merged.totalAssets,'100');assert.equal(merged.status,'settled');
  assert.deepEqual(merged.messages.map(m=>m.id),['p','s','f']);
});
test('DB observations matching archived NAV and cumulative P&L retain estimated history only',()=>{
  const prior=archived('2026-03-31',120,20);
  const current={...prior,quality:'broker_reconciled',cashflowCoverageFrom:null};
  const same=mergeDailyReport(prior,current);
  assert.equal(same.quality,'broker_reconciled');
  assert.equal(same.performanceBasis,'archived_cumulative');
  const result=calculatePerformance([archived('2026-03-01',100,0),same],[],'SOXL',when);
  assert.equal(result.summary.profit,'20.00000000');
  assert.equal(result.summary.estimated,true);
  assert.equal(mergeDailyReport(prior,{...current,totalAssets:'130'}).performanceBasis,undefined);
  assert.equal(mergeDailyReport(undefined,current).performanceBasis,undefined);
});
test('migration grants only reporting reads; retry/correction revisions preserve history',async()=>{
  const db=new PGlite();
  try{
    await db.exec('create role anon; create role authenticated; create role service_role; create table public.orders(id int);');
    await db.exec(await readFile(new URL('../../integrations/reporting.sql',import.meta.url),'utf8'));
    await db.exec(await readFile(new URL('../../integrations/20260920130000_add_legacy_reports.sql',import.meta.url),'utf8'));
    await db.exec('set role service_role');
    const publish=async b=>(await db.query('select public.my_stock_publish($1::jsonb) as revision',[JSON.stringify(b)])).rows[0].revision;
    const a=await publish(batch());assert.equal(await publish(batch()),a);
    assert.equal(await publish(batch({capturedAt:'2026-09-18T08:01:00Z'})),a);
    const b=await publish(batch({capturedAt:'2026-09-18T08:02:00Z',nav:'150'}));assert.ok(b>a);
    const c=await publish(batch({capturedAt:'2026-09-18T08:03:00Z'}));assert.ok(c>b);
    await db.exec('reset role; set role my_stock_reader');
    assert.equal((await db.query('select count(*)::int as count from reporting.publication_batches')).rows[0].count,3);
    await assert.rejects(db.query('select * from public.orders'),/permission denied/);
    await assert.rejects(db.query("delete from reporting.publication_batches"),/permission denied/);
    await assert.rejects(publish(batch()),/permission denied/);
    await db.exec('reset role; set role anon');
    await assert.rejects(db.query('select * from reporting.publication_batches'),/permission denied/);
    await assert.rejects(publish(batch()),/permission denied/);
  }finally{await db.close();}
});
