import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { PGlite } from '@electric-sql/pglite';
import { latestBatchesSQL } from '../database.mjs';
import { calculatePerformance, performanceWithPeriods, periodStart } from '../performance.mjs';
import { normalizeBatches, mergeDailyReport, closingQuotes, isEmptyOrderPlan } from '../reports-v2.mjs';

const report=(date,nav,extra={})=>({id:'SOXL-'+date,investment:'SOXL',date,currency:'USD',status:'settled',totalAssets:String(nav),quality:'broker_reconciled',cashEvents:[],cashflowCoverageFrom:'2026-01-01',...extra});
const when=new Date('2026-04-01T12:00:00Z');
test('corrected settlements choose numeric revision 11 over 9 at the same observation time',async()=>{
  const db=new PGlite();
  try {
    await db.exec(`create schema reporting; create table reporting.publication_batches (
      revision bigint, portfolio_id text, business_date date, stage text, captured_at timestamptz, investment text, payload jsonb);
      insert into reporting.publication_batches select r,'soxl_live','2026-09-21','settled','2026-09-21T20:00:00Z','SOXL',jsonb_build_object('revision',r)
      from unnest(array[9,10,11]) r;`);
    const result=await db.query(latestBatchesSQL,['SOXL']);
    assert.equal(result.rows.length,1);assert.equal(result.rows[0].revision,'11');
    assert.equal(result.rows[0].payload.revision,11);
  }finally{await db.close();}
});
test('closing prices match the selected market date, deduplicate portfolios and calculate percent units',()=>{
  const quote={symbol:'SOXL',date:'2026-09-21',close:120,previousClose:100};
  assert.deepEqual(closingQuotes([quote,quote,{...quote,symbol:'MU'},{...quote,date:'2026-09-20'}],'2026-09-21','SOXL'),
    [{symbol:'SOXL',name:'SOXL',date:'2026-09-21',currency:'USD',close:120,change:20,changePercent:20}]);
  assert.equal(closingQuotes([{...quote,previousClose:null}],'2026-09-21','SOXL')[0].changePercent,null);
  assert.equal(closingQuotes([{...quote,close:0}],'2026-09-21','SOXL').length,0);
  assert.equal(closingQuotes([{...quote,close:90}],'2026-09-21','SOXL')[0].changePercent,-10);
  assert.deepEqual(closingQuotes([{...quote,symbol:'0193T0'},{...quote,symbol:'0194T0'}],'2026-09-21','HYXL').map(q=>q.symbol),['0193T0']);
});
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
test('September archive/live settlements retain monthly profit without verified ledger coverage',()=>{
  const live=(date,nav,pnl,extra={})=>report(date,nav,{cashflowCoverageFrom:null,cumulativePnl:pnl,...extra});
  const hyxl={investment:'HYXL',currency:'KRW'};
  const rows=[archived('2026-08-31',150140.01,40791.77),live('2026-09-21',159635.73,50287.49),
    live('2026-09-30',161496.93,52148.69),
    archived('2026-08-31',162409369,39409369,{...hyxl,id:'HYXL-opening'}),
    live('2026-09-07',168002173,44993518,{...hyxl,id:'HYXL-deposit-1'}),
    live('2026-09-28',170243023,45768528,{...hyxl,id:'HYXL-deposit-2'}),
    live('2026-09-30',170701966,46227471,{...hyxl,id:'HYXL-closing'})];
  const now=new Date('2026-10-01T12:00:00Z');
  const soxl=calculatePerformance(rows,[],'SOXL',now).months[0];
  assert.equal(soxl.profit,'11356.92000000');assert.equal(soxl.cashflow,'0.00000000');
  assert.equal(soxl.coverage,'complete');assert.equal(soxl.estimated,true);
  const hy=calculatePerformance(rows,[],'HYXL',now).months[0];
  assert.equal(hy.profit,'6818102.00000000');assert.equal(hy.cashflow,'1474495.00000000');
  assert.ok(Number(hy.returnPercent)>4.19&&Number(hy.returnPercent)<4.20);
  const rates=rows.map(r=>({date:r.date,usdKrw:1000}));
  const all=calculatePerformance(rows,rates,'all',now).months[0];
  assert.equal(all.profit,'18175022.00000000');assert.equal(all.cashflow,'1474495.00000000');
  assert.equal(all.coverage,'complete');assert.equal(all.estimated,true);
});
test('live capital fallback requires reconciled P&L and keeps verified ledger priority',()=>{
  const rows=[report('2026-02-27',100,{cumulativePnl:0,cashflowCoverageFrom:null}),
    report('2026-03-31',210,{cumulativePnl:10,cashflowCoverageFrom:null})];
  assert.equal(calculatePerformance(rows,[],'SOXL',when).months[0].profit,'10.00000000');
  for(const extra of [{quality:'incomplete'},{quality:'unknown'},{cumulativePnl:null}]) {
    const result=calculatePerformance([rows[0],{...rows[1],...extra}],[],'SOXL',when);
    assert.equal(result.months[0].profit,null);assert.equal(result.months[0].coverage,'insufficient');
  }
  const withLedger=rows.map(r=>({...r,cashflowCoverageFrom:'2026-01-01',cashEvents:[
    {id:'deposit',date:'2026-03-15',kind:'deposit',amount:'100',currency:'USD'}]}));
  const exact=calculatePerformance(withLedger,[],'SOXL',when).months[0];
  assert.equal(exact.profit,'10.00000000');assert.equal(exact.method,'modified_dietz');
  assert.ok(Number(exact.returnPercent)<10); // Uses the ledger date, not the later observed capital change.
});
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
test('cancelled empty future plan is hidden without removing active orders or zero-fill settlements',()=>{
  const monday=batch({date:'2026-09-28',stage:'plan',nav:null,
    orders:[{symbol:'0193T0.KS',side:'BUY',qty:10,limit_price:100,status:'ready'}]});
  const tuesday=batch({date:'2026-09-29',stage:'plan',nav:null,orders:[]});
  const reports=normalizeBatches([monday,tuesday],'HYXL');
  assert.equal(reports[1].hasOrderPlan,false);
  assert.equal(reports[1].plannedOrderCount,0);
  assert.deepEqual(reports.filter(r=>!isEmptyOrderPlan(r)).map(r=>r.date),['2026-09-28']);
  // The previously deployed API marked this exact empty placeholder as a plan.
  assert.equal(isEmptyOrderPlan({...reports[1],hasOrderPlan:true}),true);
  assert.equal(isEmptyOrderPlan({...reports[1],status:'closed'}),false);
  assert.equal(isEmptyOrderPlan(normalizeBatches([batch(),batch({portfolioId:'ls_main'})],'HYXL')[0]),false);
  assert.equal(isEmptyOrderPlan(normalizeBatches([batch()],'HYXL')[0]),false);
  assert.equal(isEmptyOrderPlan({...reports[1],plannedOrderCount:null}),false);
  const stalePlan={...reports[0],id:reports[1].id,date:reports[1].date};
  assert.equal(isEmptyOrderPlan(mergeDailyReport(stalePlan,reports[1])),true);
  const submitted={...stalePlan,messages:[{id:'execution',date:monday.capturedAt,
    text:'주문 제출\n- 매수 KODEX 10주 @ ₩100 / ₩1,000 LOC · 제출 완료'}]};
  assert.equal(isEmptyOrderPlan(mergeDailyReport(submitted,reports[1])),false);
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
test('execution corrections preserve cancelled and filled states at the original submission time',()=>{
  const createdAt='2026-10-02T14:27:44Z';
  const source=batch({investment:'SOXL',portfolioId:'soxl_live',currency:'USD',date:'2026-10-02',
    stage:'execution',capturedAt:'2026-10-02T15:25:00Z',orders:[
      {id:'cancelled',symbol:'SOXL',side:'SELL',qty:49,order_price:170,status:'skipped',created_at:createdAt},
      {id:'filled',symbol:'SOXL',side:'BUY',qty:2,order_price:150,status:'success',created_at:createdAt}]});
  const message=normalizeBatches([source],'SOXL')[0].messages[0];
  assert.equal(message.date,createdAt);
  assert.match(message.text,/49주 @ \$170 \/ \$8,330 취소/);
  assert.match(message.text,/2주 @ \$150 \/ \$300 체결 완료/);
  assert.doesNotMatch(message.text,/제출 완료/);
  assert.equal(normalizeBatches([{...source,activityAt:'2026-10-02T14:28:00Z'}],'SOXL')[0].messages[0].date,
    '2026-10-02T14:28:00Z');
});
test('settled SENT orders are unfilled; partial fills show only the remaining quantity',()=>{
  const source=batch({orders:[{id:'a',symbol:'0193T0.KS',side:'BUY',qty:10,limit_price:100,status:'SENT',filled_qty:4}],
    evidence:{fills:[{order_id:'a',symbol:'0193T0.KS',qty:4,price:99}]}});
  const text=normalizeBatches([source],'HYXL')[0].messages[0].text;
  assert.match(text,/KODEX 4주 @ ₩99 \/ ₩396 지정가 · 체결 완료/);
  assert.match(text,/KODEX 6주 @ ₩100 \/ ₩600 미체결/);
  assert.doesNotMatch(text,/제출 완료/);
});
test('SOXL matched fill evidence avoids duplicating full fills as unfilled',()=>{
  const source=batch({investment:'SOXL',portfolioId:'soxl_live',currency:'USD',orders:[
    {id:'a',symbol:'SOXL',side:'sell',qty:10,order_price:100,status:'filled',trade_type:'main'}],
    evidence:{fills:[['a',{matchedQty:10,matchedAmount:1010}]]}});
  const text=normalizeBatches([source],'SOXL')[0].messages[0].text;
  assert.match(text,/10주 @ \$101 \/ \$1,010 방식 미확인 · 체결 완료/);
  assert.doesNotMatch(text,/미체결|main/);
});
test('fill method comes from actual execution evidence and splits LIMIT / LOC partial executions',()=>{
  const source=batch({investment:'SOXL',portfolioId:'soxl_live',currency:'USD',orders:[
    {id:'a',symbol:'SOXL',side:'buy',qty:10,order_price:100,orderType:'LOC'}],
    evidence:{fills:[['a',{matchedQty:10,matchedAmount:1060,executions:[
      {qty:4,amount:400,orderType:'LIMIT'},{qty:6,amount:660,orderType:'LOC'}]}]]}});
  const text=normalizeBatches([source],'SOXL')[0].messages[0].text;
  assert.match(text,/4주 @ \$100 \/ \$400 지정가 · 체결 완료/);
  assert.match(text,/6주 @ \$110 \/ \$660 LOC · 체결 완료/);
  assert.doesNotMatch(text,/10주|미체결/);
  source.evidence.fills[0][1].executions[0].orderType='MARKET';
  assert.match(normalizeBatches([source],'SOXL')[0].messages[0].text,/시장가 · 체결 완료/);
});
test('HYXL KRX fills show actual market / limit submission rather than strategy LOC plan',()=>{
  const source=batch({orders:[
    {id:'market',symbol:'0193T0.KS',side:'SELL',qty:2,limit_price:null,order_type:'MOC'},
    {id:'limit',symbol:'0193T0.KS',side:'BUY',qty:3,limit_price:100,order_type:'LOC'}],evidence:{fills:[
      {order_id:'market',symbol:'0193T0',qty:2,price:110},{order_id:'limit',symbol:'0193T0',qty:3,price:99}]}});
  const text=normalizeBatches([source],'HYXL')[0].messages[0].text;
  assert.match(text,/2주 @ ₩110 \/ ₩220 시장가 · 체결 완료/);
  assert.match(text,/3주 @ ₩99 \/ ₩297 지정가 · 체결 완료/);
  assert.doesNotMatch(text,/LOC · 체결 완료/);
});
test('missing execution methods are explicit and inconsistent split metadata cannot duplicate fills',()=>{
  const source=batch({investment:'SOXL',portfolioId:'soxl_live',currency:'USD',orders:[
    {id:'a',symbol:'SOXL',side:'sell',qty:10,order_price:100}],
    evidence:{fills:[['a',{matchedQty:10,matchedAmount:1000,executions:[{qty:20,amount:2000,orderType:'LOC'}]}]]}});
  const text=normalizeBatches([source],'SOXL')[0].messages[0].text;
  assert.match(text,/10주 @ \$100 \/ \$1,000 방식 미확인 · 체결 완료/);
  assert.doesNotMatch(text,/20주|LOC|미체결/);
});
test('SOXL summary ignores historical, non-SOXL and zero fills and counts orders rather than fragments',()=>{
  const source=batch({investment:'SOXL',portfolioId:'soxl_live',currency:'USD',details:[{id:'bad',title:'체결',text:'250건 체결'}],orders:[
    {id:'a',symbol:'SOXL',us_date:'2026-09-18',side:'buy',qty:10,order_price:100},
    {id:'zero',symbol:'SOXL',us_date:'2026-09-18',side:'buy',qty:3,order_price:90},
    {id:'old',symbol:'SOXL',us_date:'2026-09-17',side:'buy',qty:99,order_price:80},
    {id:'manual',symbol:'MU',us_date:'2026-09-18',side:'buy',qty:50,order_price:70}],
    evidence:{fills:[['old',{matchedQty:99,matchedAmount:7920}],['manual',{matchedQty:50,matchedAmount:3500}],
      ['a',{matchedQty:4,matchedAmount:400}],['a',{matchedQty:6,matchedAmount:600}],['zero',{matchedQty:0,matchedAmount:0}]]}});
  const result=normalizeBatches([source],'SOXL')[0];
  assert.equal(result.details.find(d=>d.title==='체결').text,'1건 체결');
  assert.doesNotMatch(result.messages[0].text,/MU|99주|NaN|Infinity/);
  assert.match(result.messages[0].text,/3주.*미체결/);
  source.evidence.fills=source.evidence.fills.filter(f=>f[0]!=='a');
  const empty=normalizeBatches([source],'SOXL')[0];
  assert.equal(empty.details.find(d=>d.title==='체결').text,'없음');
  assert.match(empty.messages[0].text,/체결 없음/);
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
