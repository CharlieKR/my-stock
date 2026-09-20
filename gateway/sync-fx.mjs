// Run on a daily schedule, independent of app traffic. Uses only a restricted FX writer.
import { databasePool } from './database.mjs';
const url=process.env.MY_STOCK_FX_DATABASE_URL;
if(!url)throw new Error('MY_STOCK_FX_DATABASE_URL is required');
const from=process.argv[2]??new Date(Date.now()-10*86400000).toISOString().slice(0,10);
if(!/^\d{4}-\d{2}-\d{2}$/.test(from))throw new Error('Expected YYYY-MM-DD');
const response=await fetch(`https://api.frankfurter.dev/v1/${from}..?base=USD&symbols=KRW`,{signal:AbortSignal.timeout(20000)});
if(!response.ok)throw new Error('FX source unavailable');
const data=await response.json();
const pool=databasePool(url);const client=await pool.connect();
try{
  const role=await client.query('select current_user as name');
  if(role.rows[0].name!=='my_stock_fx_writer')throw new Error('Dedicated FX writer role required');
  await client.query('begin');
  for(const [date,rates] of Object.entries(data.rates)){
    if(!(rates.KRW>0))continue;
    await client.query(`insert into reporting.fx_rates(rate_date,usd_krw,provider,available_at) values($1,$2,'Frankfurter',now())
      on conflict(rate_date) do update set usd_krw=excluded.usd_krw,updated_at=now(),available_at=case when reporting.fx_rates.usd_krw=excluded.usd_krw then reporting.fx_rates.available_at else excluded.available_at end`,[date,String(rates.KRW)]);
  }
  await client.query('commit');console.log('FX rates saved');
}catch(e){await client.query('rollback');throw e;}finally{client.release();await pool.end();}
