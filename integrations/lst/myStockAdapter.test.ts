import test from "node:test";
import assert from "node:assert/strict";
import { mkdtemp,readFile,rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { publishLstReporting } from "./myStockAdapter";

test("execution observations preserve terminal states and later status reversals without moving submission time",async()=>{
  const enabled=process.env.MY_STOCK_REPORTING_ENABLED,oldDir=process.env.MY_STOCK_OUTBOX_DIR;
  const dir=await mkdtemp(join(tmpdir(),"my-stock-status-"));
  try {
    process.env.MY_STOCK_REPORTING_ENABLED="true";process.env.MY_STOCK_OUTBOX_DIR=dir;
    const createdAt="2026-10-02T14:27:44Z";
    const states=["pending","skipped","success","failed","cancelled","rejected"];
    let orders=states.map((status,id)=>({id:String(id),symbol:"SOXL",us_date:"2026-10-02",qty:1,status,kis_order_no:String(id+1),created_at:createdAt}));
    const published:any[]=[];
    const sb={from:(table:string)=>{
      const q:any={};for(const key of ["select","eq","in","lte","order","range"])q[key]=()=>q;
      q.abortSignal=async()=>({data:table==="strategies"?[{id:"strategy"}]:table==="orders"?orders:[],error:null});return q;
    },rpc:(_name:string,{batch}:{batch:any})=>{published.push(batch);return {abortSignal:async()=>({error:null})};}};
    await publishLstReporting("2026-10-02","execution",{capturedAt:"2026-10-02T15:20:00Z"},()=>sb);
    assert.deepEqual(published[0].orders.map((o:any)=>o.status),["SUBMITTED","skipped","success","failed","cancelled","rejected"]);
    assert.equal(published[0].activityAt,createdAt);assert.equal(published[0].capturedAt,"2026-10-02T15:20:00Z");
    orders=[{...orders[0],status:"skipped"}];
    await publishLstReporting("2026-10-02","execution",{capturedAt:"2026-10-02T15:25:00Z"},()=>sb);
    orders=[{...orders[0],status:"pending"}];
    await publishLstReporting("2026-10-02","execution",{capturedAt:"2026-10-02T15:30:00Z"},()=>sb);
    assert.equal(published[1].orders[0].status,"skipped");assert.equal(published[2].orders[0].status,"SUBMITTED");
    assert.ok(published[2].capturedAt>published[1].capturedAt);
    assert.equal(published[2].activityAt,createdAt);
  } finally {
    if(enabled===undefined)delete process.env.MY_STOCK_REPORTING_ENABLED;else process.env.MY_STOCK_REPORTING_ENABLED=enabled;
    if(oldDir===undefined)delete process.env.MY_STOCK_OUTBOX_DIR;else process.env.MY_STOCK_OUTBOX_DIR=oldDir;
    await rm(dir,{recursive:true,force:true});
  }
});

test("settlement observation survives reporting read failure without a broker call",async()=>{
  const enabled=process.env.MY_STOCK_REPORTING_ENABLED, oldDir=process.env.MY_STOCK_OUTBOX_DIR;
  const dir=await mkdtemp(join(tmpdir(),"my-stock-observation-"));
  try {
    process.env.MY_STOCK_REPORTING_ENABLED="true";process.env.MY_STOCK_OUTBOX_DIR=dir;
    const unavailable=()=>({from:()=>{throw new Error("reporting read unavailable");}});
    const summary={actualTotalAsset:110.01,stockEval:80,totalBudget:100,totalReturn:10.01,todayNetPnl:1};
    await publishLstReporting("2026-09-18","settled",{summary,quality:"broker_reconciled",capturedAt:"2026-09-18T21:20:00Z"},unavailable);
    const saved=JSON.parse(await readFile(join(dir,"inputs/2026-09-18-settled.json"),"utf8"));
    assert.deepEqual(saved.opts.summary,summary);assert.equal(saved.opts.capturedAt,"2026-09-18T21:20:00Z");
    assert.equal(saved.date,"2026-09-18");
  }finally{
    if(enabled===undefined)delete process.env.MY_STOCK_REPORTING_ENABLED;else process.env.MY_STOCK_REPORTING_ENABLED=enabled;
    if(oldDir===undefined)delete process.env.MY_STOCK_OUTBOX_DIR;else process.env.MY_STOCK_OUTBOX_DIR=oldDir;
    await rm(dir,{recursive:true,force:true});
  }
});

test("settlement publishes RP income rather than cash adjustment and only today's SOXL fills",async()=>{
  const enabled=process.env.MY_STOCK_REPORTING_ENABLED,oldDir=process.env.MY_STOCK_OUTBOX_DIR;
  const dir=await mkdtemp(join(tmpdir(),"my-stock-summary-"));
  try {
    process.env.MY_STOCK_REPORTING_ENABLED="true";process.env.MY_STOCK_OUTBOX_DIR=dir;
    let published:any;
    const rows:any={strategies:[{id:"strategy"}],orders:[{id:"today",symbol:"SOXL",us_date:"2026-09-18",qty:2}],
      strategy_cashflows:[{id:1,us_date:"2026-09-18",type:"income",amount:10,client_ref:"ls-rp-income:1",metadata:{lsTransactionDate:"20260918"}}]};
    const sb={from:(table:string)=>{
      const q:any={};for(const key of ["select","eq","in","lte","order","range"])q[key]=()=>q;
      q.abortSignal=async()=>({data:rows[table],error:null});return q;
    },rpc:(_name:string,{batch}:{batch:any})=>{published=batch;return {abortSignal:async()=>({error:null})};}};
    await publishLstReporting("2026-09-18","settled",{summary:{actualTotalAsset:1100,stockEval:80,totalBudget:1000,totalReturn:100,todayNetPnl:10,
      rpIncomeTotal:10,rpIncomeToday:10,reportingBasis:{fills:[["old",{matchedQty:100}],["today",{matchedQty:2,matchedAmount:80}]]}},
      details:[{id:"RP",title:"RP",text:"RP 평가보정 +$55.00"},{id:"fills",title:"체결",text:"250건 체결"}],quality:"broker_reconciled"},()=>sb);
    assert.equal(published.details[0].text,"누적 +$10.00 (+$10.00)");
    assert.equal(published.details.length,1);
    assert.deepEqual(published.evidence.fills,[["today",{matchedQty:2,matchedAmount:80}]]);
    assert.equal(published.nav,"1100");
  } finally {
    if(enabled===undefined)delete process.env.MY_STOCK_REPORTING_ENABLED;else process.env.MY_STOCK_REPORTING_ENABLED=enabled;
    if(oldDir===undefined)delete process.env.MY_STOCK_OUTBOX_DIR;else process.env.MY_STOCK_OUTBOX_DIR=oldDir;
    await rm(dir,{recursive:true,force:true});
  }
});
