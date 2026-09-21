import pg from 'pg';
import { readFile } from 'node:fs/promises';
import { readFileSync } from 'node:fs';
import { rootCertificates } from 'node:tls';
import { createHash } from 'node:crypto';
const pools = new Map();
export function databasePool(connectionString) {
  if (!pools.has(connectionString)) {
    const url = new URL(connectionString);
    // Do not let connection-string SSL options silently disable certificate verification.
    for (const key of ['sslmode','sslcert','sslkey','sslrootcert']) url.searchParams.delete(key);
    pools.set(connectionString,new pg.Pool({connectionString:url.href,max:2,connectionTimeoutMillis:5000,
      idleTimeoutMillis:10000,statement_timeout:10000,allowExitOnIdle:true,
      ssl:{rejectUnauthorized:true,ca:[...rootCertificates,readFileSync(new URL('./certs/supabase-prod-ca-2021.crt',import.meta.url),'utf8')]}}));
  }
  return pools.get(connectionString);
}
export const digest = value => createHash('sha256').update(JSON.stringify(value)).digest('hex');
export const latestBatchesSQL = `select distinct on (b.portfolio_id,b.business_date,b.stage) b.payload,b.revision::text as revision
  from reporting.publication_batches b where b.investment=$1
  order by b.portfolio_id,b.business_date,b.stage,b.captured_at desc,b.revision desc`;
export async function sourceDatabase(investment) {
  const connection = process.env[investment==='SOXL'?'MY_STOCK_LST_DATABASE_URL':'MY_STOCK_KST_DATABASE_URL'];
  if(!connection) return {investment,status:'unconfigured',message:'DB 연결 준비 중 · 보관된 과거 기록을 표시합니다.',batches:[],rates:[]};
  const client=await databasePool(connection).connect();
  try {
    await client.query('begin isolation level repeatable read read only');
    const role=await client.query('select current_user as name');
    if(role.rows[0].name!=='my_stock_reader') throw new Error('Dedicated reader role required');
    const result=await client.query(latestBatchesSQL,[investment]);
    const rates=investment==='SOXL'?await client.query('select rate_date::text as date,usd_krw::text as "usdKrw",available_at as "availableAt",provider from reporting.fx_rates order by rate_date'): {rows:[]};
    const archive=await client.query('select payload from reporting.legacy_reports where investment=$1 order by business_date',[investment]);
    await client.query('commit');
    return {investment,status:'ready',message:'Supabase 정산 기록',batches:result.rows.map(r=>({...r.payload,revision:r.revision})),rates:rates.rows,archive:archive.rows.map(r=>r.payload)};
  } catch { await client.query('rollback').catch(()=>{}); throw new Error(investment+' DB 조회 실패'); }
  finally {client.release();}
}
export async function readJSON(path,fallback) {try{return JSON.parse(await readFile(path,'utf8'));}catch(e){if(e.code==='ENOENT')return fallback;throw e;}}
