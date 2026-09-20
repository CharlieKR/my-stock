import { join } from 'node:path';
import { mkdir, writeFile, rename } from 'node:fs/promises';
import Decimal from 'decimal.js';
import { dataDir } from './config.mjs';
import { sourceDatabase, digest, readJSON } from './database.mjs';
import { performanceWithPeriods, calculationVersion } from './performance.mjs';

const sum=(rows,key)=>rows.some(r=>r[key]===null||r[key]===undefined)?null:rows.reduce((a,r)=>a.plus(r[key]),new Decimal(0)).toString();
const number=value=>Number(value).toLocaleString('ko-KR',{maximumFractionDigits:2});
function orderLine(order,currency){
  const side=String(order.side??'').toUpperCase()==='BUY'?'매수':String(order.side??'').toUpperCase()==='SELL'?'매도':order.side??'';
  const symbol=order.symbol??order.name??'SOXL';
  const qty=Number(order.qty??order.quantity??0);
  const price=order.limit_price??order.order_price??order.price;
  if(price===null||price===undefined||!Number.isFinite(Number(price)))return `- ${side} ${symbol} ${number(qty)}주 · 가격 미정`;
  const mark=currency==='KRW'?'₩':'$';
  const amount=new Decimal(price).times(qty);
  const type=order.order_type??order.trade_type??order.type??'';
  return `- ${side} ${symbol} ${number(qty)}주 @ ${mark}${number(price)} / ${mark}${number(amount)}${type?` ${type}`:''}`;
}
export function normalizeBatches(batches,investment) {
  const ids=investment==='SOXL'?['soxl_live']:(process.env.MY_STOCK_HYXL_PORTFOLIOS??'kiwoom_main,ls_main').split(',');
  const scoped=batches.filter(b=>b.investment===investment&&ids.includes(b.portfolioId));
  const latestByPortfolio=ids.map(id=>scoped.filter(b=>b.portfolioId===id).sort((a,b)=>a.capturedAt.localeCompare(b.capturedAt)).at(-1));
  const cashEvents=latestByPortfolio.flatMap(b=>(b?.cashEvents??[]).map(e=>({...e,id:b.portfolioId+':'+e.id})));
  const coverage=latestByPortfolio.every(b=>b?.cashflowCoverageFrom)?latestByPortfolio.map(b=>b.cashflowCoverageFrom).sort().at(-1):null;
  return [...new Set(scoped.map(b=>b.date))].sort().map(date=>{
    const day=scoped.filter(b=>b.date===date);
    const parts=ids.map(id=>day.filter(b=>b.portfolioId===id&&b.stage==='settled').at(-1));
    const complete=parts.every(p=>p&&p.nav!==null&&p.nav!==undefined&&p.quality!=='incomplete');
    const present=parts.filter(Boolean);
    const nav=complete?sum(present,'nav'):null;
    const pnl=complete?sum(present,'cumulativePnl'):null;
    const principal=complete?sum(present,'principal'):null;
    const capturedAt=day.map(b=>b.capturedAt).sort().at(-1);
    const details=day.flatMap(b=>b.details.map(d=>({...d,id:b.portfolioId+':'+b.stage+':'+d.id})));
    const planBatches=day.filter(b=>b.stage==='plan');
    const plannedOrderCount=planBatches.reduce((count,b)=>count+(b.orders?.length??0),0);
    const quality=complete&&present.every(b=>b.quality==='broker_reconciled')?'broker_reconciled':'incomplete';
    const valueDate=present.map(b=>b.capturedAt).sort().at(-1)??capturedAt;
    return {id:investment+'-'+date,investment,date,currency:investment==='SOXL'?'USD':'KRW',
      status:complete?'settled':day.every(b=>b.stage==='closed')?'closed':'pending',
      totalAssets:nav,stockValue:complete?sum(present,'stockValue'):null,cash:complete?sum(present,'cash'):null,
      cumulativePnl:pnl,cumulativeReturn:pnl!==null&&principal!==null&&new Decimal(principal).gt(0)?new Decimal(pnl).div(principal).times(100).toString():null,
      dailyPnl:complete?sum(present,'dailyPnl'):null,dailyPnlLabel:'오늘 손익',details,
      rawText:details.map(d=>d.title+'\n'+d.text).join('\n\n'),slackURL:'',threadTS:'',updatedAt:capturedAt,
      quality,availableDate:new Date(valueDate).toLocaleDateString('en-CA',{timeZone:'Asia/Seoul'}),
      cashEvents,cashflowCoverageFrom:coverage,
      hasOrderPlan:planBatches.length>0,plannedOrderCount,
      messages:day.flatMap(b=>[
        ...b.details.map(d=>({id:b.portfolioId+':'+b.stage+':'+d.id,text:d.title+'\n'+d.text,date:b.capturedAt})),
        ...(b.orders?.length?[{id:b.portfolioId+':'+b.stage+':orders',date:b.capturedAt,
          text:(b.stage==='plan'?'주문 계획':'주문 기록')+' · '+b.portfolioId+'\n'+b.orders.map(o=>orderLine(o,b.currency)).join('\n')
            +'\n'+(b.stage==='plan'?'제출 전 계획이며 실제 체결과 다를 수 있습니다.':'체결 상태는 주문별 기록을 확인해 주세요.')}]:[]),
        ...(b.evidence?.fills?.length?[{id:b.portfolioId+':'+b.stage+':fills',date:b.capturedAt,
          text:'체결 결과 · '+b.portfolioId+'\n'+b.evidence.fills.flatMap(f=>{
            if(Array.isArray(f)) {
              const o=b.orders?.find(o=>String(o.id)===String(f[0]));
              return o?[`${o.symbol} · ${o.side} · ${f[1].matchedQty}주 · 체결금액 ${f[1].matchedAmount}`]:[];
            }
            return [`${f.symbol} · ${f.qty}주 × ${f.price} · ${f.filled_at??''}`];
          }).join('\n')}]:[])
      ])};
  });
}

async function persist(path,value){await mkdir(dataDir,{recursive:true,mode:0o700});const tmp=path+'.tmp';await writeFile(tmp,JSON.stringify(value),{mode:0o600});await rename(tmp,path);}
let pending;
let computed;
export function loadV2(){return pending??=(buildV2().finally(()=>{pending=undefined;}));}
async function buildV2(){
  const archive=await readJSON(join(dataDir,'legacy-reports.json'),{reports:[],fxRates:[]});
  const saved=await readJSON(join(dataDir,'source-cache-v2.json'),{});
  const states=await Promise.all(['SOXL','HYXL'].map(async investment=>{
    try {
      const source=await sourceDatabase(investment);
      if(source.status==='unconfigured'&&saved[investment]?.batches?.length)return {...saved[investment],investment,status:'cached',message:'DB 연결 전 · 마지막으로 저장된 주문과 정산 기록을 표시합니다.'};
      return source;
    }
    catch {return {...saved[investment],investment,status:'error',message:'DB 동기화 실패 · 마지막 기록을 표시합니다.',batches:saved[investment]?.batches??[],rates:saved[investment]?.rates??[]};}
  }));
  for(const s of states) if(s.status==='ready')saved[s.investment]=s;
  await persist(join(dataDir,'source-cache-v2.json'),saved);
  const legacy=archive.reports.map(r=>{
    const hasOrderPlan=r.hasOrderPlan??(r.status==='pending'&&(r.messages?.some(m=>/주문표|주문 계획/.test(m.text))||r.details.some(d=>/주문표|주문금액/.test(d.title+' '+d.text))));
    return {...r,quality:'legacy_archive',cashEvents:[],cashflowCoverageFrom:null,hasOrderPlan:Boolean(hasOrderPlan),
      plannedOrderCount:r.plannedOrderCount??null,availableDate:r.date,slackURL:'',threadTS:'',
      details:[...r.details,{id:'archive',title:'보관 기록',text:'이전 리포트에서 보존한 과거 기록입니다.'}],messages:r.messages??[]};
  });
  const map=new Map(legacy.map(r=>[r.id,r]));
  for(const s of states)for(const r of normalizeBatches(s.batches,s.investment))map.set(r.id,r);
  const reports=[...map.values()].sort((a,b)=>a.date.localeCompare(b.date)||a.id.localeCompare(b.id));
  const rates=new Map((archive.fxRates??[]).map(r=>[r.date,r]));
  for(const s of states)for(const r of s.rates)rates.set(r.date,r);
  const fxRates=[...rates.values()].sort((a,b)=>a.date.localeCompare(b.date));
  const now=new Date();
  const datasetId=digest([dataDir,...['MY_STOCK_LST_DATABASE_URL','MY_STOCK_KST_DATABASE_URL'].map(k=>{
    const v=process.env[k];if(!v)return '';const u=new URL(v);return u.host+u.pathname;
  })]).slice(0,24);
  const revision=digest([datasetId,reports,fxRates,states.map(s=>[s.status,s.message]),calculationVersion,now.toLocaleDateString('en-CA',{timeZone:'Asia/Seoul'})]);
  const performance=computed?.revision===revision?computed.performance:Object.fromEntries(['all','SOXL','HYXL'].map(scope=>[scope,performanceWithPeriods(reports,fxRates,scope,now)]));
  computed={revision,performance};
  return {schemaVersion:2,datasetId,revision,calculationVersion,generatedAt:now.toISOString(),reports,fxRates,
    fxSource:'저장된 일별 USD/KRW 기준환율',fxMessage:fxRates.length?null:'환율 수집이 필요합니다.',performance,
    sources:states.map(s=>({investment:s.investment,status:s.status,
      message:s.message,lastSyncedAt:s.batches.map(b=>b.capturedAt).sort().at(-1)??null}))};
}
