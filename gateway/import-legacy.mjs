// One-time local archive. Does not connect to Slack or a broker.
import { readFile, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { dataDir } from './config.mjs';
import { digest } from './database.mjs';
const source=JSON.parse(await readFile(join(dataDir,'reports.json'),'utf8'));
await writeFile(join(dataDir,'legacy-reports.json'),JSON.stringify({...source,archivedAt:new Date().toISOString(),sourceHash:digest(source)}),{flag:'wx',mode:0o600});
console.log(`Archived ${source.reports.length} historical reports. No Slack requests made.`);
