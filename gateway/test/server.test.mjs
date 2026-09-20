import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawn } from 'node:child_process';
import { once } from 'node:events';

test('reader API enforces auth, read-only methods and cached envelope', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'my-stock-test-'));
  const cache = { schemaVersion: 1, generatedAt: new Date().toISOString(), reports: [], fxRates: [], sources: [] };
  await writeFile(join(directory, 'reports.json'), JSON.stringify(cache));
  const child = spawn(process.execPath, ['gateway/server.mjs'], { cwd: new URL('../../', import.meta.url), env: { ...process.env, PORT: '0', MY_STOCK_DATA_DIR: directory, MY_STOCK_READER_TOKEN: 'test-reader-only' }, stdio: ['ignore', 'pipe', 'pipe'] });
  try {
    const [chunk] = await once(child.stdout, 'data');
    const port = chunk.toString().match(/127\.0\.0\.1:(\d+)/)?.[1];
    assert.ok(port && port !== '0');
    const base = `http://127.0.0.1:${port}`;
    assert.equal((await fetch(base + '/v1/reports')).status, 401);
    const headers = { Authorization: 'Bearer test-reader-only' };
    assert.equal((await fetch(base + '/v1/reports', { method: 'POST', headers })).status, 405);
    assert.deepEqual(await (await fetch(base + '/v1/reports', { headers })).json(), cache);
    assert.equal((await fetch(base + '/v1/reports/SOXL-2026-09-18/thread', { headers })).status, 404);
    assert.equal((await fetch(base + '/unknown', { headers })).status, 404);
    // An app refresh must not race a separate historical backfill writer.
    const old = { ...cache, generatedAt: '2026-01-01T00:00:00Z' };
    await writeFile(join(directory, 'reports.json'), JSON.stringify(old));
    await writeFile(join(directory, 'sync.lock'), String(process.pid));
    assert.deepEqual(await (await fetch(base + '/v1/reports', { headers })).json(), old);
  } finally {
    child.kill(); await once(child, 'exit'); await rm(directory, { recursive: true, force: true });
  }
});

test('v2 works without Slack, persists source cache and invalidates ETag on historical correction',async()=>{
  const directory=await mkdtemp(join(tmpdir(),'my-stock-v2-'));
  const archive={reports:[],fxRates:[]};
  await writeFile(join(directory,'legacy-reports.json'),JSON.stringify(archive));
  const child=spawn(process.execPath,['gateway/server.mjs'],{cwd:new URL('../../',import.meta.url),env:{...process.env,PORT:'0',MY_STOCK_DATA_DIR:directory,MY_STOCK_READER_TOKEN:'test',MY_STOCK_LST_DATABASE_URL:'',MY_STOCK_KST_DATABASE_URL:''},stdio:['ignore','pipe','pipe']});
  try{
    const [chunk]=await once(child.stdout,'data');const port=chunk.toString().match(/127\.0\.0\.1:(\d+)/)[1];
    const url=`http://127.0.0.1:${port}/v2/reports`;const headers={Authorization:'Bearer test'};
    const first=await fetch(url,{headers});assert.equal(first.status,200);
    const data=await first.json();assert.equal(data.schemaVersion,2);assert.equal(data.sources[0].status,'unconfigured');
    const etag=first.headers.get('etag');assert.ok(etag);
    assert.equal((await fetch(url,{headers:{...headers,'If-None-Match':etag}})).status,304);
    await writeFile(join(directory,'legacy-reports.json'),JSON.stringify({...archive,fxRates:[{date:'2026-09-18',usdKrw:1400}]}));
    const revised=await fetch(url,{headers:{...headers,'If-None-Match':etag}});assert.equal(revised.status,200);assert.notEqual(revised.headers.get('etag'),etag);
    assert.equal((await fetch(url,{headers:{Authorization:'Bearer wrong'}})).status,401);
  }finally{child.kill();await once(child,'exit');await rm(directory,{recursive:true,force:true});}
});
