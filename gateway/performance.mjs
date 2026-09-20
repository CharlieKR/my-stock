import Decimal from 'decimal.js';
Decimal.set({precision:32});
export const calculationVersion='nav-ledger-dietz-2.3-verified-history';
const D=v=>new Decimal(v);
const days=(a,b)=>(Date.parse(b)-Date.parse(a))/86400000;
const text=v=>v===null?null:D(v).toFixed(8);
const latest=(rows,date)=>rows.filter(r=>r.date<=date && days(r.date,date)<=7).at(-1);

// Archived reports retain cumulative P&L but not a verified cash ledger.
// Changes in NAV minus cumulative P&L estimate capital changes; never treat
// deposits, or the first appearance of another investment, as investment gain.
function inferHistoricalPerformance(span,scope) {
  const complete=p=>p.parts.every(r=>r.cumulativePnl!==null&&r.cumulativePnl!==undefined);
  const lastMissing=span.findLastIndex(p=>!complete(p));
  const observed=span.slice(lastMissing+1);
  if(observed.length<2)return null;
  const start=observed[0],end=observed.at(-1);
  let net=D(0),weighted=D(0);
  const duration=Math.max(1,days(start.date,end.date));
  for(let index=1;index<observed.length;index++) {
    const before=observed[index-1],after=observed[index];
    for(const current of after.parts) {
      const prior=before.parts.find(r=>r.investment===current.investment);
      const capital=r=>D(r.totalAssets).minus(r.cumulativePnl);
      // A newly observed account enters at its full observed NAV. Its earlier
      // accumulated profit predates this combined series and is not a return.
      const flow=prior?capital(current).minus(capital(prior)):D(current.totalAssets);
      const converted=flow.times(scope==='all'&&current.currency==='USD'?after.fx:1);
      net=net.plus(converted);
      weighted=weighted.plus(converted.times(days(after.date,end.date)/duration));
    }
    if(before.parts.some(r=>!after.parts.some(p=>p.investment===r.investment)))return null;
  }
  const profit=D(end.assets).minus(start.assets).minus(net);
  const denominator=D(start.assets).plus(weighted);
  return {start,profit,returnPercent:denominator.gt(0)?profit.div(denominator).times(100):null,net,
    shortened:lastMissing>=0};
}

export function periodStart(end,period) {
  if(period==='all')return null;
  const d=new Date(end+'T00:00:00Z');
  if(period==='week'){d.setUTCDate(d.getUTCDate()-6);return d.toISOString().slice(0,10);}
  const months={month:1,quarter:3,halfYear:6,year:12}[period];
  if(!months)throw new Error('Invalid period');
  const day=d.getUTCDate();d.setUTCDate(1);d.setUTCMonth(d.getUTCMonth()-months);
  d.setUTCDate(Math.min(day,new Date(Date.UTC(d.getUTCFullYear(),d.getUTCMonth()+1,0)).getUTCDate()));
  d.setUTCDate(d.getUTCDate()+1);
  return d.toISOString().slice(0,10);
}

export function calculatePerformance(reports,rates,scope,now=new Date(),range={}) {
  const investments=scope==='all'?['SOXL','HYXL']:[scope];
  const valued=reports.filter(r=>investments.includes(r.investment)&&r.status==='settled'&&r.totalAssets!==null);
  const series=Object.fromEntries(investments.map(i=>[i,valued.filter(r=>r.investment===i).sort((a,b)=>a.date.localeCompare(b.date))]));
  const sortedRates=[...rates].sort((a,b)=>a.date.localeCompare(b.date));
  const points=[];
  const dates=[...new Set(valued.map(r=>scope==='all'?r.availableDate??r.date:r.date))].sort();
  for(const date of dates){
    if(date>now.toLocaleDateString('en-CA',{timeZone:'Asia/Seoul'}))continue;
    // Before an investment's first recorded date show the investments already
    // observed. Once records begin, missing/stale valuations are never zeroed.
    const active=scope==='all'?investments.filter(i=>reports.some(r=>r.investment===i&&r.date<=date)):investments;
    const parts=active.map(i=>scope==='all'
      ? series[i].filter(r=>(r.availableDate??r.date)<=date&&days(r.availableDate??r.date,date)<=7).at(-1)
      : latest(series[i],date));
    const rate=scope==='all'?latest(sortedRates,date):{usdKrw:'1'};
    if(!parts.length||parts.some(p=>!p)||!rate)continue;
    const assets=parts.reduce((v,p)=>v.plus(D(p.totalAssets).times(scope==='all'&&p.currency==='USD'?rate.usdKrw:1)),D(0));
    points.push({date,assets:text(assets),fx:text(rate.usdKrw),constituentIDs:parts.map(p=>p.id),
      quality:parts.every(p=>p.quality==='broker_reconciled')&&(!rate.availableAt||rate.availableAt<=date+'T14:59:59.999Z')?'broker_reconciled':'estimated',
      carried:parts.some(p=>p.date!==date),includedInvestments:active,parts});
  }
  const months=[];
  const visible=points.filter(p=>(!range.from||p.date>=range.from)&&(!range.to||p.date<=range.to));
  let summary=null;
  // Each latest source publication contains its complete ledger. Dedup is already performed by the reader.
  const latestReports=investments.map(i=>series[i].at(-1)).filter(Boolean);
  const groups=[...new Set(visible.map(p=>p.date.slice(0,7)))].sort().reverse().map(month=>({month,inside:visible.filter(p=>p.date.startsWith(month)),boundary:range.from&&range.from>month+'-01'?range.from:month+'-01'}));
  if(visible.length)groups.push({month:'',inside:visible,boundary:range.from??visible[0].date});
  for(const {month,inside,boundary} of groups){
    const end=inside.at(-1);
    const previous=points.filter(p=>p.date<boundary&&days(p.date,boundary)<=7).at(-1);
    let start=previous??inside[0];
    const active=end.parts.map(r=>r.investment);
    const activeReports=latestReports.filter(r=>active.includes(r.investment));
    const stableComposition=start.parts.length===end.parts.length;
    let valid=stableComposition&&activeReports.length===active.length&&activeReports.every(r=>r.cashflowCoverageFrom&&r.cashflowCoverageFrom<=start.date);
    const relevant=activeReports.flatMap(r=>r.cashEvents??[]).filter(e=>e.date>start.date&&e.date<=end.date&&['deposit','withdraw','transfer_in','transfer_out'].includes(e.kind));
    // Cross-investment transfers require an explicitly paired transferId; never guess from amounts.
    const paired=new Set();
    if(scope==='all') for(const e of relevant.filter(e=>e.transferId)){
      const peers=relevant.filter(p=>p.transferId===e.transferId);
      if(peers.length===2&&peers.some(p=>p.kind==='transfer_in')&&peers.some(p=>p.kind==='transfer_out')&&peers[0].date===peers[1].date) paired.add(e.transferId);
      else valid=false; // in-transit valuation not established
    }
    let net=D(0),weighted=D(0),hasFlow=false;
    for(const e of relevant){
      if(paired.has(e.transferId))continue;
      const rate=scope==='all'&&e.currency==='USD'?latest(sortedRates,e.date)?.usdKrw:'1';
      if(!rate){valid=false;continue;}
      const signed=D(e.amount).times(['withdraw','transfer_out'].includes(e.kind)?-1:1).times(rate);
      net=net.plus(signed); weighted=weighted.plus(signed.times(days(e.date,end.date)/Math.max(1,days(start.date,end.date))));hasFlow=true;
    }
    let profit=valid?D(end.assets).minus(start.assets).minus(net):null;
    const denominator=D(start.assets).plus(weighted);
    let pct=profit!==null&&denominator.gt(0)?profit.div(denominator).times(100):null;
    let inferred=null;
    // Keep historical estimates when DB NAV/P&L exactly match the frozen archive.
    // New or corrected DB observations still require verified ledger coverage.
    const span=points.filter(p=>p.date>=start.date&&p.date<=end.date);
    if(!valid&&span.every(p=>p.parts.every(r=>r.quality==='legacy_archive'||r.performanceBasis==='archived_cumulative'))) {
      inferred=inferHistoricalPerformance(span,scope);
      if(inferred){start=inferred.start;profit=inferred.profit;pct=inferred.returnPercent;net=inferred.net;}
    }
    const current=month===now.toLocaleDateString('en-CA',{timeZone:'Asia/Seoul',year:'numeric',month:'2-digit'}).slice(0,7);
    const result={month,startDate:start.date,endDate:end.date,startAssets:start.assets,endAssets:end.assets,
      profit:text(profit),returnPercent:text(pct),cashflow:valid||inferred?text(net):null,
      partial:!previous||(!valid&&!inferred)||Boolean(inferred?.shortened)||current||(Boolean(month)&&boundary>month+'-01'),
      estimated:profit!==null&&(Boolean(inferred)||hasFlow||inside.some(p=>p.quality!=='broker_reconciled')),
      method:inferred?'inferred_capital_dietz':hasFlow?'modified_dietz':'simple',
      reason:inferred?(inferred.shortened?`누적 손익이 확인되는 ${start.date}부터 계산한 추정 수익입니다.`:'과거 누적 손익과 자산에서 원금 변화를 추정한 수익입니다.'):
        valid?null:'누적 손익 또는 입출금 원장이 부족해 수익을 계산할 수 없습니다.'};
    if(month)months.push(result);else summary=result;
  }
  return {scope,calculationVersion,points:visible.map(({parts,...p})=>p),months,summary};
}

export function performanceWithPeriods(reports,rates,scope,now=new Date()) {
  const full=calculatePerformance(reports,rates,scope,now);
  const end=full.points.at(-1)?.date;
  if(!end)return full;
  return {...full,periods:Object.fromEntries(['week','month','quarter','halfYear','year'].map(period=>[
    period,calculatePerformance(reports,rates,scope,now,{from:periodStart(end,period),to:end})
  ]))};
}
