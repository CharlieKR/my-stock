import assert from "node:assert/strict";
import { mkdtemp, mkdir, readFile, rm, unlink, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { markJobRunDone } from "./jobRunState";
import { syncLstExecutablePlan } from "./myStockExecutablePlan";
import type { OrderRow } from "./validatedOrders";

const date = "2026-11-13";
const buy: OrderRow = { symbol: "SOXL", side: "매수", qty: 64, price: 65.19, orderType: "LOC", rowIndex: 4 };
const sell: OrderRow = { symbol: "SOXL", side: "매도", qty: 228, price: 0, orderType: "MOC", rowIndex: 5 };

test("edits, holds, release and deletion follow the executable plan without changing it", async () => {
  const cwd = await mkdtemp(join(tmpdir(), "my-stock-plan-"));
  try {
    const data = join(cwd, "data");
    const inputs = join(data, "my-stock-outbox", "inputs");
    await mkdir(inputs, { recursive: true });
    const tide = join(data, "validated_orders_ttulsa.json");
    const saved = join(inputs, `${date}-plan.json.saved`);
    const writePlan = (orders: OrderRow[], usDate = date) => writeFile(tide, JSON.stringify({
      strategyName: "ttulsa", source: "ttulsa_engine", usDate, orders, validatedAt: "2026-11-13T07:00:00Z",
      validationSummary: "원본 검증 주문표",
    }));
    const batches: Array<Array<OrderRow>> = [];
    const run = (holdQty = "0") => syncLstExecutablePlan(date, async (usDate, opts) => {
      assert.equal(usDate, date);
      batches.push(opts.orders);
      await writeFile(saved, JSON.stringify({ date, stage: "plan", opts }));
    }, { cwd, outboxDir: "data/my-stock-outbox", holdQty });

    assert.equal(await run(), "inactive");
    await writePlan([buy, sell]);
    const original = await readFile(tide, "utf8");
    assert.equal(await run(), "published");
    assert.deepEqual(batches.at(-1)?.map(o => o.qty), [64, 228]);
    assert.equal(await run("228"), "published");
    assert.deepEqual(batches.at(-1)?.map(o => o.qty), [64]);
    assert.equal(await readFile(tide, "utf8"), original);
    assert.equal(await run("228"), "unchanged");
    assert.equal(await run(), "published");
    assert.deepEqual(batches.at(-1)?.map(o => o.qty), [64, 228]);

    await writePlan([{ ...buy, qty: 21, price: 64.05 }]);
    assert.equal(await run(), "published");
    assert.deepEqual(batches.at(-1)?.map(({ qty, price }) => ({ qty, price })), [{ qty: 21, price: 64.05 }]);
    await writeFile(tide, '{"orders":');
    await assert.rejects(run(), SyntaxError);
    assert.equal(batches.at(-1)?.[0]?.qty, 21);

    await writePlan([]);
    assert.equal(await run(), "published");
    assert.deepEqual(batches.at(-1), []);
    await writePlan([buy]);
    await run();
    await unlink(tide);
    assert.equal(await run(), "published");
    assert.deepEqual(batches.at(-1), []);

    await writePlan([buy], "2026-11-12");
    assert.equal(await run(), "unchanged");
    await writePlan([buy, sell]);
    assert.equal(await run("invalid"), "published");
    assert.deepEqual(batches.at(-1)?.map(o => o.qty), [64]);
    await writePlan([buy]);
    await run();
    markJobRunDone("execute_orders", date, {}, cwd);
    await unlink(tide);
    assert.equal(await run(), "inactive");
    assert.equal(batches.at(-1)?.[0]?.qty, 64);
  } finally {
    await rm(cwd, { recursive: true, force: true });
  }
});
