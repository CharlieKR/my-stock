import http from 'node:http';
import { timingSafeEqual } from 'node:crypto';
import { readerToken, sourceConfig } from './config.mjs';
import { readCache, syncReports, slackRead } from './sync.mjs';
import { loadV2 } from './reports-v2.mjs';

const token = readerToken();
let pendingSync;
const threads = new Map();
function authorized(req) {
  const actual = Buffer.from(req.headers.authorization ?? '');
  const expected = Buffer.from(`Bearer ${token}`);
  return actual.length === expected.length && timingSafeEqual(actual, expected);
}
function send(res, code, data) {
  res.writeHead(code, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff' });
  res.end(JSON.stringify(data));
}

const server = http.createServer(async (req,res) => {
  if (!authorized(req)) return send(res, 401, { error: '읽기 전용 연결 키를 확인해 주세요.' });
  if (req.method !== 'GET') return send(res, 405, { error: 'Read only' });
  const url = new URL(req.url, 'http://localhost');
  try {
    if (url.pathname.startsWith('/v2/')) {
      const data = await loadV2();
      const etag = '"' + data.revision + '"';
      if (url.pathname === '/v2/reports' || url.pathname === '/v2/performance') {
        if (req.headers['if-none-match'] === etag) {
          res.writeHead(304, {'ETag':etag,'Cache-Control':'private, no-cache'}); return res.end();
        }
        res.setHeader('ETag',etag);
        if(url.pathname==='/v2/reports')return send(res,200,data);
        const scope=url.searchParams.get('scope')??'all';
        if(!['all','SOXL','HYXL'].includes(scope))return send(res,400,{error:'Invalid scope'});
        return send(res,200,{...data.performance[scope],datasetId:data.datasetId,revision:data.revision});
      }
      if(url.pathname==='/v2/health'||url.pathname==='/v2/overview')return send(res,200,{sources:data.sources,generatedAt:data.generatedAt});
      const detail=url.pathname.match(/^\/v2\/daily\/(SOXL|HYXL)\/(\d{4}-\d{2}-\d{2})$/);
      if(detail){const r=data.reports.find(r=>r.id===detail[1]+'-'+detail[2]);return r?send(res,200,{messages:r.messages,partial:false}):send(res,404,{error:'해당 날짜의 데이터가 없습니다.'});}
      return send(res,404,{error:'Not found'});
    }
    if (url.pathname === '/v1/reports') {
      const cached = await readCache();
      const age = cached.generatedAt ? Date.now() - Date.parse(cached.generatedAt) : Infinity;
      if (age > 60000 && process.env.MY_STOCK_ENABLE_LEGACY_SLACK === 'true') {
        pendingSync ??= syncReports().finally(() => { pendingSync = null; });
        await pendingSync;
      }
      return send(res, 200, await readCache());
    }
    const match = url.pathname.match(/^\/v1\/reports\/(SOXL|HYXL)-(\d{4}-\d{2}-\d{2})\/thread$/);
    if (match) {
      const id = `${match[1]}-${match[2]}`;
      const report = (await readCache()).reports.find(r => r.id === id);
      if (!report) return send(res, 404, { error: '리포트가 없습니다.' });
      if(process.env.MY_STOCK_ENABLE_LEGACY_SLACK !== 'true')return send(res,200,{messages:[],partial:false});
      const saved = threads.get(id);
      if (saved && Date.now() - saved.time < 60000) return send(res, 200, saved.value);
      const config = sourceConfig(match[1]);
      if (!config.token || !config.channel) return send(res, 503, { error: 'Slack 연결 정보를 확인해 주세요.' });
      const messages = [];
      let cursor = '';
      for (let page = 0; page < 20; page++) {
        const result = await slackRead('conversations.replies', config, { ts: report.threadTS, ...(cursor ? { cursor } : {}) });
        messages.push(...(result.messages ?? []).filter(m => m.ts !== report.threadTS).map(m => ({ id: m.ts, text: m.text ?? '', date: new Date(Number(m.ts) * 1000).toISOString() })));
        cursor = result.response_metadata?.next_cursor ?? '';
        if (!cursor) break;
      }
      const value = { messages, partial: Boolean(cursor) };
      threads.set(id, { time: Date.now(), value });
      if (threads.size > 100) threads.delete(threads.keys().next().value);
      return send(res, 200, value);
    }
    return send(res, 404, { error: 'Not found' });
  } catch (e) { return send(res, 502, { error: e.message ?? '데이터를 가져오지 못했습니다.' }); }
});

const port = Number(process.env.PORT ?? 8787);
const host = process.env.HOST ?? '127.0.0.1';
server.listen(port, host, () => console.log(`My Stock reader listening on ${host}:${server.address().port}. Connection key is in .local/reader-token.`));
