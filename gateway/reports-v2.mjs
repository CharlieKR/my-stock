import { join } from 'node:path';
import { mkdir, writeFile, rename } from 'node:fs/promises';
import Decimal from 'decimal.js';
import { dataDir } from './config.mjs';
import { sourceDatabase, digest, readJSON } from './database.mjs';
import { performanceWithPeriods, calculationVersion } from './performance.mjs';

const sum=(rows,key)=>rows.some(r=>r[key]===null||r[key]===undefined)?null:rows.reduce((a,r)=>a.plus(r[key]),new Decimal(0)).toString();
const number=value=>Number(value).toLocaleString('ko-KR',{maximumFractionDigits:2});
function groupedOrderLines(orders,suffix){
  const groups=new Map();
  for(const order of orders){
    const note=typeof suffix==='function'?suffix(order):suffix;
    const key=JSON.stringify([order.symbol,order.side,order.limit_price??order.order_price??order.price,order.order_type??order.type,order.currency,note]);
    const current=groups.get(key);
    if(current)current.order.qty+=Number(order.qty??order.quantity??0);
    else groups.set(key,{order:{...order,qty:Number(order.qty??order.quantity??0)},note});
  }
  return [...groups.values()].map(({order,note})=>orderLine(order,order.currency,note));
}
function orderLine(order,currency,suffix=''){
  const side=String(order.side??'').toUpperCase()==='BUY'?'매수':String(order.side??'').toUpperCase()==='SELL'?'매도':order.side??'';
  const rawSymbol=order.symbol??order.name??'SOXL';
  const symbol=({'0193T0':'KODEX','0194T0':'ACE'})[rawSymbol.replace(/\.KS$/u,'')]??rawSymbol;
  const qty=Number(order.qty??order.quantity??0);
  const price=order.limit_price??order.order_price??order.price;
  if(price===null||price===undefined||!Number.isFinite(Number(price)))return `- ${side} ${symbol} ${number(qty)}주 · 가격 미정`;
  const mark=currency==='KRW'?'₩':'$';
  const amount=new Decimal(price).times(qty);
  const type=order.order_type??order.type??'';
  const note=[type,suffix].filter(Boolean).join(' · ');
  return `- ${side} ${symbol} ${number(qty)}주 @ ${mark}${number(price)} / ${mark}${number(amount)}${note?` ${note}`:''}`;
}
const statusLabel=status=>{
  const value=String(status??'').toUpperCase();
  if(['SENT','SUBMITTED','OPEN','READY'].includes(value))return value==='READY'?'예정':'제출 완료';
  if(['FILLED','DONE'].includes(value))return '체결 완료';
  if(['REJECTED','FAILED'].includes(value))return '거부';
  if(['CANCELED','CANCELLED','SKIPPED'].includes(value))return '취소';
  return status??'';
};
function timelineMessages(day){
  const messages=[];
  for(const stage of ['plan','execution','settled']){
    const batches=day.filter(b=>b.stage===stage);
    if(!batches.length)continue;
    const date=batches.map(b=>b.capturedAt).sort().at(-1);
    const orders=batches.flatMap(b=>(b.orders??[]).map(o=>({...o,currency:b.currency})));
    if(stage==='plan'&&orders.length){
      messages.push({id:'plan-orders',date,text:'주문표 생성\n'+groupedOrderLines(orders,'예정').join('\n')});
    }
    if(stage==='execution'&&orders.length){
      messages.push({id:'execution-orders',date,text:'주문 제출\n'+groupedOrderLines(orders,o=>statusLabel(o.status)||'제출').join('\n')});
    }
    if(stage==='settled'){
      const fills=batches.flatMap(b=>(b.evidence?.fills??[]).map(f=>({fill:f,batch:b})));
      const fillLines=fills.flatMap(({fill,batch})=>{
        if(Array.isArray(fill)){
          const order=batch.orders?.find(o=>String(o.id)===String(fill[0]));
          return order?[orderLine({...order,qty:fill[1].matchedQty,limit_price:new Decimal(fill[1].matchedAmount).div(fill[1].matchedQty)},batch.currency,'체결 완료')]:[];
        }
        const order=batch.orders?.find(o=>String(o.id)===String(fill.order_id));
        return [orderLine({...fill,side:order?.side,symbol:fill.symbol??order?.symbol,order_type:order?.order_type,limit_price:fill.price},batch.currency,'체결 완료')];
      });
      const matched=new Map();
      for(const {fill} of fills){
        const id=String(Array.isArray(fill)?fill[0]:fill.order_id);
        const qty=Number(Array.isArray(fill)?fill[1].matchedQty:fill.qty);
        matched.set(id,(matched.get(id)??0)+qty);
      }
      const unfilled=orders.flatMap(o=>{
        const filled=matched.get(String(o.id))??Number(o.filled_qty??0);
        const remaining=Number(o.qty??o.quantity??0)-filled;
        return remaining>0?[{...o,qty:remaining}]:[];
      });
      const sections=[fillLines.length?fillLines.join('\n'):'체결 없음'];
      if(unfilled.length)sections.push('미체결/거부\n'+groupedOrderLines(unfilled,o=>{
        const status=String(o.status??'').toUpperCase();
        return ['REJECTED','FAILED'].includes(status)?'거부':
          ['CANCELED','CANCELLED'].includes(status)?'취소':'미체결';
      }).join('\n'));
      messages.push({id:'settled-fills',date,text:'체결 결과\n'+sections.join('\n\n')});
    }
  }
  return messages.sort((a,b)=>a.date.localeCompare(b.date));
}

export function mergeDailyReport(archived,current){
  if(!archived)return current;
  const stage=message=>/체결|결과/u.test(message.text.split('\n')[0])?'settled':
    /제출|실행/u.test(message.text.split('\n')[0])?'execution':'plan';
  const messages=new Map((archived.messages??[]).map(m=>[stage(m),m]));
  for(const m of current.messages??[])messages.set(stage(m),m);
  const combined=[...messages.values()].sort((a,b)=>a.date.localeCompare(b.date));
  // An execution-only observation must not erase a previously settled NAV.
  if(current.status!=='settled'&&archived.status==='settled'){
    return {...archived,messages:combined,updatedAt:current.updatedAt,
      hasOrderPlan:current.hasOrderPlan||archived.hasOrderPlan,
      plannedOrderCount:current.plannedOrderCount||archived.plannedOrderCount};
  }
  const verifiedArchive=archived.quality==='legacy_archive'&&
    ['totalAssets','cumulativePnl'].every(key=>archived[key]!=null&&current[key]!=null&&new Decimal(archived[key]).eq(current[key]));
  return {...current,messages:combined,
    ...(verifiedArchive?{performanceBasis:'archived_cumulative'}:{})};
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
    const sourceDetails=day.filter(b=>b.stage==='settled').flatMap(b=>b.details.map(d=>({...d,id:b.portfolioId+':'+b.stage+':'+d.id})));
    const settledFills=present.flatMap(b=>b.evidence?.fills??[]);
    const details=[...sourceDetails];
    if(complete&&!details.some(d=>d.title==='체결'))details.push({id:investment+':settled:fills',title:'체결',
      text:settledFills.length?`${settledFills.length}건 체결`:'없음'});
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
      messages:timelineMessages(day)};
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
  const historical=new Map(archive.reports.map(r=>[r.id,r]));
  for(const s of states)for(const r of s.archive??[])historical.set(r.id,r);
  const legacy=[...historical.values()].map(r=>{
    const hasOrderPlan=r.hasOrderPlan??(r.status==='pending'&&(r.messages?.some(m=>/주문표|주문 계획/.test(m.text))||r.details.some(d=>/주문표|주문금액/.test(d.title+' '+d.text))));
    return {...r,quality:'legacy_archive',cashEvents:[],cashflowCoverageFrom:null,hasOrderPlan:Boolean(hasOrderPlan),
      plannedOrderCount:r.plannedOrderCount??null,availableDate:r.date,slackURL:'',threadTS:'',
      details:[...r.details,{id:'archive',title:'보관 기록',text:'이전 리포트에서 보존한 과거 기록입니다.'}],messages:r.messages??[]};
  });
  const map=new Map(legacy.map(r=>[r.id,r]));
  for(const s of states)for(const r of normalizeBatches(s.batches,s.investment))map.set(r.id,mergeDailyReport(map.get(r.id),r));
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
