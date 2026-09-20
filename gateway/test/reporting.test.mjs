import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { PGlite } from '@electric-sql/pglite';
import { calculatePerformance, performanceWithPeriods, periodStart } from '../performance.mjs';
import { normalizeBatches } from '../reports-v2.mjs';

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
  assert.equal(normalizeBatches([batch(),batch({portfolioId:'ls_main',nav:'200'})],'HYXL')[0].totalAssets,'300');
});
test('migration grants only reporting reads; retry/correction revisions preserve history',async()=>{
  const db=new PGlite();
  try{
    await db.exec('create role anon; create role authenticated; create role service_role; create table public.orders(id int);');
    await db.exec(await readFile(new URL('../../integrations/reporting.sql',import.meta.url),'utf8'));
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
